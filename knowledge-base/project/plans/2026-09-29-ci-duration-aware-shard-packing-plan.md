---
title: "chore(ci): duration-aware shard packing — last-N timing aggregation, untimed-suite floor, arbitrary-K emission (#9232)"
type: chore
date: 2026-09-29
slug: ci-duration-aware-shard-packing
branch: feat-one-shot-9232-duration-aware-shard-packing
issue: 9232
closes: 9232
priority: medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# chore(ci): duration-aware shard packing — last-N aggregation, floor weights, arbitrary-K emission

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** User-Brand Impact (scope-out bullet corrected to cover
BOTH `apps/web-platform/infra/*.tsv` matches, not just the durations table),
Proposed Solution (the floor degrade now names BOTH `die` sites it replaces;
input-source precedence replaces the earlier mutual-exclusion claim, matching
`main()`'s provenance-pairing convention), Technical Considerations
(`expected_legs` must stay bound to the workflow N under `--legs`;
`fetch_timings_from_dir` fixture-shape note), Research Insights (deepen-round
gate ledger + four more learnings applied), References (the `8006` probe is
retired — live precedent is `deploy-script-tests-legs-8736.sh`).
**Research agents used:** none spawnable — this harness exposes no Task/Skill
spawn tool; every conditional halt below was run inline with shell evidence
cited. `Reviewed-Coverage: sequential-fallback` — no independent review is
claimed.

### Key Improvements

1. The n-mismatch commit-shape is refused at write time, not merely linted —
   a `K != N` manifest committed silently degrades every leg to positional.
2. `src=floor` provenance in the durations table stops a floor estimate from
   ever being re-aggregated as a measurement.
3. The `#8231` consumption surface needs zero `test-all.sh` machinery:
   `--durations` + `--legs` + `--manifest` emit a table the existing
   `SOLEUR_SHARD_MANIFEST`/`SCRIPTS_SHARD` seams already consume.

### New Considerations Discovered

- The all-floor degrade replaces two distinct `die` sites in `main()`
  (~lines 322, 336), not one — an implementation that converts only the
  first still dies on the disjoint-labels shape.
- `fetch_timings_from_dir` only applies its artifact-name filter to
  CI-named subdirs; the battery must cover both the filtered and
  merge-whole fixture shapes.
- `apps/web-platform/infra/suite-shard-legs.tsv` (regenerated) is itself a
  sensitive-path-regex match (`apps/[^/]+/infra/`), not just the new
  durations file — the scope-out bullet was corrected accordingly.

## Overview

The `test-scripts` CI legs consume a committed label→leg manifest produced
offline by `scripts/regenerate-shard-manifest.py`. The generator is already
sticky-LPT (longest-processing-time) over CI-measured suite durations (#8006,
ADR-240) — issue #9232's "positional manifest slicing" framing is stale. What
is NOT stale: the generator packs against a **single run's snapshot**, gives
**registered-but-untimed suites no weight at all** (they fall back to a cksum
hash at runtime), and can only emit at the leg count declared in the workflow
matrix. On run 36622402829 (2026-09-29) leg 3/7 measured 18.8 min of suite
time against siblings' 5.4–10.9 min: `test-all-affected` had drifted
191s→384s and `test-contention` 60s→135s since the Sep-25 snapshot.

This plan extends the existing generator to aggregate timings across the last
N green runs, assign untimed suites a documented default weight so they enter
the packed table, emit the same packed grouping at an arbitrary K for #8231's
local parallel scheduler, and commit the aggregated duration table as the
single duration source both consumers read.

## Problem Statement / Motivation

Three independently-verified gaps sit under the issue's symptom:

1. **Single-run snapshot.** `fetch_timings_from_run` merges exactly one run's
   `suite-timings-scripts-*` artifacts. Any suite that drifted since the last
   regen (or spiked/absented on that one run) carries a stale weight until the
   next manual regen. Measured on run 36622402829: light-leg suite-time totals
   were 9.0 / 10.9 / **18.8** / 9.6 / 5.4 / 9.2 / 9.8 min — a 3.5× spread, with
   the 19m39s wall clock the issue cites.
2. **Untimed labels carry zero weight.** 518 registered `scripts` labels vs
   506 tabled manifest rows (measured this session) — 12 registered suites
   hash-fall onto legs at effective weight 0. New heavy suites (the
   `lint-orphan-test-suites-mutations-a`/`_b` class, ~325 s each) can land on
   an already-heavy leg purely by hash lottery.
3. **No consumer surface at K ≠ workflow N.** The packed grouping is bound to
   `read_ci_leg_count()`'s parse of the matrix; #8231's local parallel
   scheduler needs the same durations packed at a host-chosen worker count W —
   without requiring a dev host to re-download CI artifacts.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "`test-scripts` CI legs shard a regenerated manifest positionally (`SCRIPTS_SHARD` is an ordinal slice)" | Manifest mode is already duration-aware sticky-LPT (ADR-240, `assign()` in `scripts/regenerate-shard-manifest.py`; the runtime `_shard_selects` is a table lookup). Positional round-robin survives only as the degrade path (absent/n-mismatched manifest). | Do not re-implement LPT — extend it: last-N aggregation, floor weights, arbitrary-K emission. |
| "or the existing timing floor if history is unavailable" | No timing floor exists anywhere: registered-but-untimed labels are not tabled (hash fallback at runtime), and zero usable timings is a hard `die` exit 2 (`main()` "no usable suite timings"). `_suite_budget_ms` is an advisory per-suite reporter, not a packing weight. | Introduce the documented floor: `median` of the group's measured labels, falling back to a fixed constant when nothing is measured; an all-floor manifest is a WARN-and-produce degrade, not a die. |
| "the same packed groups must drive the local `test-all.sh` parallel scheduler (#8231)" | No arbitrary-K emission exists — n is parsed from the workflow matrix. But the consumption seam already exists: `SOLEUR_SHARD_MANIFEST` accepts an absolute path and `SCRIPTS_SHARD=k/N` bounds any N; `--enumerate` honors both (`run_suite` calls `_shard_selects` before enumerate dispatch). | Add `--legs K` emission + a committed `suite-durations-*.tsv` per group so the local packing needs zero `gh` calls; #8231 spawns W shard-filtered runners. |
| "shard 3/7 held 193 suites" | That leg's artifact holds 96 *timed* rows (the 193 figure likely counts skip/declined rows too); the imbalance is duration-weighted, not count-weighted. | The fix is weight-aware; the unit battery asserts per-leg ms, not per-leg counts. |

## Proposed Solution

Extend `scripts/regenerate-shard-manifest.py` (one file, all three groups
uniformly — the generator already multiplexes `--group light|heavy|infra`):

1. **Last-N aggregation.** `green_main_runs(workflow, n)` lists the N most
   recent successful main runs of the group's workflow (`per_page=N` on the
   existing runs-list call); each run merges its group's artifacts as today
   (intra-run cross-leg `max`, exclusion rules unchanged). Per label the
   weight is the **median** across runs (mean of the two middle values for an
   even sample count — deterministic). `--runs N` (default 5); `--run <id>`
   remains as an explicit single-run override (equivalent to N=1 over that
   run).
2. **Documented floor for untimed labels.** A registered label absent from
   every run's timings is tabled at `floor_ms` = median of the group's
   measured labels, or the fixed constant `DEFAULT_SUITE_MS = 60000` when no
   label measured at all (all-floor degrade: WARN, still writes — a
   count-balanced packing is strictly better than a die). This replaces TWO
   `die` sites in `main()`, not one: `no usable suite timings` (~line 322)
   and `no timed label is a registered {group} suite` (~line 336) — both
   become WARN-and-floor. Floor rows are marked `src=floor` in the durations
   table so a later aggregation never entrenches its own estimate as
   "measured".
3. **Arbitrary-K emission.** `--legs K` overrides the workflow-derived n for
   the emitted table. Refusal: `--write` to the group's *default committed
   manifest* with `K != workflow N` exits 2 — a committed n-mismatch silently
   degrades every leg to positional while reading as applied; that shape must
   be refused, not warned. Any K is permitted with an explicit `--manifest`
   path or in dry-run (the sanctioned K-simulation path for future
   rebalance decisions like #8881).
4. **Committed durations artifact.** On `--write`, the generator also writes
   `suite-durations.tsv` beside each group's manifest
   (`scripts/suite-durations.tsv`, `scripts/suite-durations-heavy.tsv`,
   `apps/web-platform/infra/suite-durations.tsv`): rows
   `label<TAB>ms<TAB>src` (`src` ∈ `measured|floor`), label-sorted, with the
   same `#`-comment provenance header discipline (`# group=`,
   `# generated-from-runs=<csv>`, `# default-weight-ms=<v>`). `--durations
   <path>` reads the table instead of fetching; `--durations-out <path>`
   redirects the write for fixtures. Input-source precedence mirrors the
   file's existing pairing rule (`main()` ~line 355 — provenance stamps
   whichever source actually fed): `--durations` > `--timings-dir` >
   gh (`--run`/`--runs`), never a silent mix. This is the "one duration
   source, two consumers" the issue demands: CI regen writes it, #8231's
   scheduler re-packs from it offline.
5. **`#8231` consumption contract (documentation + a generator-side test, no
   `test-all.sh` machinery changes):**

   ```bash
   python3 scripts/regenerate-shard-manifest.py \
     --durations scripts/suite-durations.tsv --legs "$W" \
     --manifest "$WORK/local-legs.tsv" --write
   # then W workers, each:
   #   SCRIPTS_SHARD=k/W SOLEUR_SHARD_MANIFEST="$WORK/local-legs.tsv" \
   #     bash scripts/test-all.sh scripts
   ```

   The emitted file satisfies the existing parse contract (`# n=W`,
   `label<TAB>leg`, legs in 1..W), so `_shard_selects` consumes it untouched.
   Shared-resource serialization across W local workers (#8163) is #8231's
   design surface, not this plan's.
6. **Provenance/report.** `GENERATOR_VERSION` → `"3"`; manifest header gains
   `# generated-from-runs=<csv>` (keeping `# generated-from-run=<latest>` —
   the lint greps `^# generated-from-run`, which prefix-matches both spellings
   either way) and `# default-weight-ms=`; the dry-run report prints per-run
   coverage, the floor value, and how many labels packed at floor.

## Technical Considerations

- **Median, not max or mean.** Max over-weights contention spikes into a
  permanent assignment (#8163 measured `orphan-process-reaper-mutation` at
  429 s contended vs 179 s isolated — a max-merge would pin the spike
  forever); mean lets one outlier drag the weight. Median requires a
  *sustained* shift (~⌈N/2⌉ elevated samples) to move a weight — the right
  hysteresis for a manual-cadence artifact. The intra-run cross-leg merge
  stays `max` (a label on two legs is a duplicate-write defect; keeping max
  preserves the existing WARN semantics).
- **Why a committed durations file rather than re-fetching in the local
  scheduler.** A W-way packing cannot be committed (W is host-dependent), so
  *something* must be re-packed locally; re-downloading ~50 artifact zips (N=5
  runs × ~10 legs) per local dispatch is not a reasonable precondition for a
  dev-host test run, and `gh` auth is not guaranteed mid-run. The committed
  table is regenerated alongside the manifest in the same `--write` call —
  same ADR-235 discipline (sorted rows, deterministic output, conflicts
  resolve by regeneration never hand-merge).
- **Insertion stability is preserved, not widened.** A suite added after the
  last regen is still untabled and still hash-falls — the ⊆ lint stays
  one-directional (`manifest ⊆ registered`) and deliberately does NOT assert
  `registered ⊆ manifest`: asserting it would force a regen (and a
  merge-conflict-prone generated-artifact diff) into every suite-adding PR.
  Floor tabling only means a suite that was registered *before* the last
  regen but never measured now carries weight.
- **`# generated-from-runs` vs the lint.** `scripts-shard-manifest.test.sh`
  asserts `grep -q "^# generated-from-run"` — the plural key satisfies the
  prefix. Both keys are written anyway (`-run=<latest>` for humans,
  `-runs=<csv>` for the real provenance).
- **`--timings-dir` becomes repeatable** (`action="append"`): each directory
  is one run's artifact set; a single dir keeps today's single-run semantics.
  This is the seam the unit battery drives multi-run fixtures through without
  `gh`. Fixture note: `fetch_timings_from_dir`'s `artifact_re` filter only
  engages on CI-named nested dirs (`suite-timings-scripts-*`); fixture dirs
  named that way exercise the filtered path, arbitrary names exercise the
  merge-whole path — the battery should cover both.
- **`expected_legs` under `--legs`:** the per-run artifact-completeness WARN
  must compare against the workflow's declared leg count (the producer side
  that actually uploads `suite-timings-scripts-*`), not the overridden K —
  `--legs` reshapes the packing, never the artifact set.
- **Precedence, not mutual exclusion.** `main()`'s existing convention
  (~line 355) is a pairing rule with honest provenance (`--run` +
  `--timings-dir` → dir wins, provenance says `local:`). The new sources slot
  into the same chain — `--durations` > `--timings-dir`(s) > gh — rather
  than introducing a second flag-combination dialect.
- **Portability:** the generator is stock python3 — already a regen
  prerequisite on dev hosts; the `#8231` recipe adds no new binary deps.
- **Determinism:** same inputs → identical data rows (ties break on label
  sort inside `assign()`; median is input-derived, not wall-clock). Header
  timestamps differ per invocation — the round-trip AC compares data rows
  only.
- **NFR register:** `knowledge-base/engineering/architecture/nfr-register.md`
  — reliability/CI-determinism only; no user-facing entry affected.

## Files to Edit

- `scripts/regenerate-shard-manifest.py` — `--runs`/`--legs`/`--durations`/
  `--durations-out` args; `green_main_runs()`; per-label median aggregation;
  floor weighting + `src` provenance; durations-table read/write; the
  default-path n-mismatch refusal; `GENERATOR_VERSION` → `"3"`; report fields.
  (Estimate ~150 net lines — the issue's "~80" was scoped before the
  durations artifact and the n-mismatch refusal existed in the design.)
- `plugins/soleur/test/regenerate-shard-manifest.test.sh` — new fixtures
  (see Test Scenarios); `MIN_CASES` bump to cover them.
- `plugins/soleur/test/scripts-shard-manifest.test.sh` — a `--- durations
  tables ---` block mirroring the manifest contract (exists, well-formed,
  `src` enum, ⊆ registered, manifest-keys == durations-keys); `MIN_CASES`
  bump.
- `.github/scripts/test/test-infra-suite-registration.sh` — the same
  durations-table coherence arm for `apps/web-platform/infra/
  suite-durations.tsv` (the infra manifest's lint lives here, not in the
  plugin suite).
- `scripts/test-all.sh` — exactly one `run_suite` line registering the new
  followthrough probe's `.test.sh` in the followthroughs registration block
  (~line 4042 region). **No change** to `_shard_selects`, the manifest
  loader, or `SCRIPTS_SHARD` parsing — the `_shard_selects` contract is an
  AC-pinned invariant.
- `.github/workflows/ci.yml` — comment-only refresh of the stale
  positional-era guidance block above the `test-scripts` matrix (~lines
  1029–1044): membership now comes from the duration-aware manifest; before
  touching K run `python3 scripts/regenerate-shard-manifest.py --legs <K>`
  dry-run instead of re-simulating round-robin.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  — regen procedure documents `--runs`/`--durations`/`--legs`, the floor
  rule, and the #8231 local-parallel recipe.
- `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`
  — amendment section (see `## Architecture Decision (ADR/C4)`).
- `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs-heavy.tsv`,
  `apps/web-platform/infra/suite-shard-legs.tsv` — regenerated under the new
  generator against the latest green main runs at work time.

## Files to Create

- `scripts/suite-durations.tsv` — light-group aggregated weights (`label`,
  `ms`, `src`), committed generated artifact.
- `scripts/suite-durations-heavy.tsv` — heavy-group counterpart.
- `apps/web-platform/infra/suite-durations.tsv` — infra-group counterpart
  (its manifest already lives in this directory — same contract).
- `scripts/followthroughs/ci-leg-balance-9232.sh` — post-merge soak probe:
  for the ≥3 most recent qualifying post-`earliest` green `ci.yml` main runs,
  sum `suite-timings-scripts-*` per leg and exit 0 only when every leg is
  ≤ ~2× the mean — excluding any leg whose largest single suite alone
  exceeds the mean (the issue's mega-suite carve-out; precedent:
  `lint-orphan-test-suites-mutations` 588.8 s on a leg by itself). Exit
  semantics per `sweep-followthroughs.sh`: 0 PASS / 1 FAIL / 2 NOT-YET /
  3 CANNOT-ESTABLISH; a run qualifies only when all 7 light legs uploaded
  artifacts.
- `scripts/followthroughs/ci-leg-balance-9232.test.sh` — synthesized-fixture
  test (no `gh` calls; `cq-test-fixtures-synthesized-only`).
- `scripts/followthroughs/ci-leg-balance-9232.sh` is registered via the one
  `run_suite` line named above.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is CI/dev-loop time. Worst case: a badly-packed manifest makes
  the worst `test-scripts` leg slower (the status quo ante), or a malformed
  durations table makes a local `#8231` worker subset wrong — both bounded by
  the runner's existing fallbacks (hash fallback, positional degrade) and by
  the ⊆ lint reddening on phantom rows.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — durations are suite labels and millisecond counts of the
  repo's own test corpus, already derivable from public CI logs.
- **Brand-survival threshold:** `none`
- `threshold: none, reason:` the only sensitive-path-regex matches are the
  two `apps/web-platform/infra/*.tsv` rows (the regenerated
  `suite-shard-legs.tsv` and the new `suite-durations.tsv`) — generated
  label→weight tables with no credentials, no provisioning input, and no
  user data; the manifest sibling already lives in that directory under the
  same contract.

## Observability

The change is offline machinery; its observable surface is the regenerated
artifacts' CI gates plus the post-merge leg-balance probe. (Included because
the Files-to-Edit set touches `apps/*/infra/` — Phase 2.9 trigger.)

```yaml
liveness_signal:
  what: "test-scripts / test-scripts-heavy leg suite-time totals within ~2x of mean, and the committed manifests' hygiene gates"
  cadence: "per CI run (timings artifacts uploaded on every leg); soak probe sweeps daily once enrolled"
  alert_target: "required `test` check (manifest lint rows) + `follow-through` issue comment on #9232 (balance probe)"
  configured_in: "plugins/soleur/test/scripts-shard-manifest.test.sh; scripts/followthroughs/ci-leg-balance-9232.sh; .github/workflows/scheduled-followthrough-sweeper.yml"
error_reporting:
  destination: "stderr of a manual regen invocation (`ERROR:`/exit 2), and GitHub Actions job log for the lint suites"
  fail_loud: "regen `die` names the failing run/artifact; lint FAIL rows name the offending label/leg; the soak probe exits 1 with the breaching leg named"
failure_modes:
  - mode: "zero usable timing history (new checkout, artifact expiry, auth failure)"
    detection: "regen WARN + all-floor degrade; report prints `floor` counts so the degrade is visible, never silent"
    alert_route: "stderr on the regen invocation; the produced manifest is still count-balanced"
  - mode: "manifest committed with n != workflow N"
    detection: "refused at --write time (exit 2) AND independently reddened by scripts-shard-manifest.test.sh's n-pin"
    alert_route: "required `test` check"
  - mode: "leg imbalance re-grows after merge (suite drift the manual regen cadence misses)"
    detection: "ci-leg-balance-9232 soak probe: any qualifying leg > ~2x mean"
    alert_route: "sweeper comments on #9232, leaves it open"
logs:
  where: "generator stdout/stderr (invoker's terminal or Actions log); probe output via the sweeper job log"
  retention: "GitHub Actions default (90 days) for CI-side output"
discoverability_test:
  command: python3 scripts/regenerate-shard-manifest.py --help
  expected_output: durations
```

## Guard Contract

### Guard 1 — duration-aware packing battery (`regenerate-shard-manifest.test.sh` extension)

**Property.** The emitted manifest's leg assignment is a deterministic
function of measured durations and the documented floor — multi-run inputs
aggregate by median, registered-but-untimed labels are tabled at the floor
weight, a `--durations` file reproduces the packing offline, and a `--write`
to the committed manifest with `K != workflow N` is refused.

**Assembly.** `scripts/regenerate-shard-manifest.py` end to end — the
fetch/merge layer (`fetch_timings_from_run`, `fetch_timings_from_dir`,
`merge_tsv`), the new aggregation + floor layer, `assign()`'s sticky-LPT
chokepoint (the single place weights become legs), `render()`'s header, and
`main()`'s arg wiring. All new behavior is driven through the existing
`--timings-dir`/`--registered-file`/`--manifest` seams plus the new
`--durations`/`--legs` seams — no `gh` in fixtures
(`cq-test-fixtures-synthesized-only`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Aggregation computes per-label **max** across runs instead of median | RED — fixture J holds two runs where suite X measures 100 ms/300 ms and the resulting weight/assignment must reflect the median (200 ms), not the max |
| 2 | Floor tabling removed (untimed labels skipped, old behavior) | RED — fixture K asserts a registered-but-untimed label appears in the manifest AND its durations row carries `src=floor` |
| 3 | Default-path n-mismatch refusal deleted | RED — fixture L runs `--legs` ≠ ci.yml N with `--write` at the default path and must exit 2 |
| 4 | `--durations` read path silently ignored (fetch path still runs) | RED — fixture M feeds a durations file whose weights differ from the timings dir; the manifest must reflect the file's weights |
| 5 | Second untimed label added beside a first compliant one | RED if the two collapse onto one leg by construction — floor labels must flow through `assign()`, not a fixed leg |
| 6 (harness) | A fixture section neutered (e.g. generator invocation stubbed to exit 0) so its checks never execute | RED — `MIN_CASES` floor bumped with the new cases; a suite that stops reaching the new cases trips the floor |
| 7 (must-pass, non-canonical) | A `--durations` file containing only `src=floor` rows | PASS — permitted input: all-floor packing must still produce a valid manifest, and floor rows must NOT be re-read as measured |

Window/ordering note: the floor→measured transition is a *state* property
across regenerations, so row 7 also pins direction — a consumed `src=floor`
row must be re-derived as floor, never entrenched as `measured`.

### Guard 2 — durations-table lint (`scripts-shard-manifest.test.sh` + `test-infra-suite-registration.sh` blocks)

**Property.** Every committed `suite-durations*.tsv` is well-formed
(`label<TAB>ms<TAB>src`, `src` ∈ {measured,floor}), covers exactly the label
set its sibling manifest covers, and contains only registered labels.

**Assembly.** The three committed tables and their sibling manifests, bound
to the same enumerated registered sets the ⊆ lint already derives — the
chokepoint is the registered-set enumeration (`--enumerate`, and the infra
filesystem enumeration), not a name list in the test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | A durations row with `src=weighed` (outside the enum) | RED |
| 2 | A durations row for an unregistered label | RED — same phantom class as the manifest ⊆ lint |
| 3 | A label present in the manifest but absent from durations | RED — manifest-keys ⊆ durations-keys |
| 4 | The lint block deleted entirely | RED — the suite's `MIN_CASES` floor and a section-presence row both trip |

## Acceptance Criteria

### Functional Requirements

- [ ] `python3 scripts/regenerate-shard-manifest.py --help` lists `--runs`,
  `--legs`, `--durations`, and `--durations-out`.
- [ ] `--runs N` aggregates per label by median across the N most recent
  green main runs of the group's workflow; `--run <id>` keeps single-run
  semantics; a run missing a leg's artifacts warns (existing
  `expected_legs` path) and contributes what it has.
- [ ] `--timings-dir` accepts multiple invocations, each treated as one run's
  artifact set for aggregation.
- [ ] A registered label absent from all timing inputs is tabled in the
  manifest and recorded `src=floor` at `floor_ms` (median-of-measured, else
  `DEFAULT_SUITE_MS`); a timings-empty invocation produces an all-floor
  manifest with WARN rather than exit 2.
- [ ] `--durations <path>` + `--durations-out <path>` round-trip: a manifest
  regenerated from a durations file is byte-identical in data rows to the
  manifest generated from the timings that produced that file.
- [ ] `--legs K --manifest <path> --write` emits a valid `n=K` table;
  `--write` to the group's default manifest with `K !=` workflow N exits 2.
- [ ] All three groups (`light`, `heavy`, `infra`) gain the same mechanics;
  the committed `suite-durations{,-heavy}.tsv` and
  `apps/web-platform/infra/suite-durations.tsv` exist, are label-sorted, and
  carry the provenance header.
- [ ] `SCRIPTS_SHARD=1/4 SOLEUR_SHARD_MANIFEST=<emitted n=4 table> bash
  scripts/test-all.sh --enumerate scripts` emits only that leg's subset and
  the W=4 union of all four emits equals the registered set — the #8231
  consumption path exercised end-to-end without editing `test-all.sh`'s
  shard machinery.
- [ ] `git diff origin/main...HEAD -- scripts/test-all.sh` contains exactly
  one hunk: the added `run_suite` registration for the probe's `.test.sh`
  (merge-base diff, not tip diff — a sibling merge to test-all.sh must not
  redden this AC).

### Non-Functional Requirements

- [ ] Regeneration stays deterministic: two runs of the generator over the
  same inputs produce byte-identical data rows (existing fixture-A property,
  extended to multi-run inputs).
- [ ] No new runtime dependencies for the runner path: `test-all.sh` gains no
  new reads, no new binaries; the generator remains stock python3.

### Quality Gates

- [ ] `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` → 0 failed
  with the raised `MIN_CASES` floor covering every new fixture.
- [ ] `bash plugins/soleur/test/scripts-shard-manifest.test.sh` → 0 failed
  including the durations-table block.
- [ ] `bash .github/scripts/test/test-infra-suite-registration.sh` → green
  with the infra durations coherence arm.
- [ ] A dry-run regen report over the latest green main runs is pasted into
  the PR evidence showing predicted per-leg totals within ~2× of the mean,
  excluding any leg dominated by a single suite exceeding the mean (the
  issue's mega-suite carve-out).
- [ ] Followthrough enrollment lands: `scripts/followthroughs/
  ci-leg-balance-9232.sh` + `.test.sh` exist, the probe is registered, and
  the plan instructs `soleur:ship` to append
  `<!-- soleur:followthrough script=scripts/followthroughs/ci-leg-balance-9232.sh earliest=<merge+3d> secrets=GH_TOKEN -->`
  + the `follow-through` label to #9232 (label verified to exist).

## Test Scenarios

- Given two timing dirs where suite X measures 100 ms and 300 ms, when the
  generator aggregates, then X's weight is the median (200 ms) and the
  manifest assignment reflects it.
- Given a registered label with no timing row in any input, when the
  generator runs, then the label is tabled at `floor_ms` and its durations
  row reads `floor`.
- Given zero usable timing rows at all, when the generator runs, then it
  WARNs and still writes a count-balanced manifest (graceful degrade).
- Given `--legs 3` with `--write` aimed at the default `suite-shard-legs.tsv`
  while ci.yml declares n=7, when the generator runs, then it exits 2 naming
  the mismatch.
- Given a durations file written by `--durations-out`, when consumed via
  `--durations` with `--legs 4 --manifest <tmp> --write`, then the emitted
  table is well-formed, `n=4`, and `SOLEUR_SHARD_MANIFEST` + `SCRIPTS_SHARD`
  consume it in `--enumerate` mode.
- Given a `src=floor` row in an input durations file, when re-aggregated,
  then it stays floor-classed (floor never launders into measured).
- Given run B lacks one leg's artifact, when `--runs` fetches A and B, then
  the partial run warns and still contributes its present legs.
- Regression: a suite added between regens (registered, untabled) still
  hash-falls — insertion stability is unchanged (asserted by the existing
  scripts-shard-manifest mutation rows staying green).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (inline — this harness exposes no subagent spawn; CTO-lens
self-assessment) Blast radius is confined to CI timing and a committed
generated artifact. The runner stays a pure lookup — the trust boundary
(offline compute → committed data → runtime lookup → deterministic fallbacks)
is ADR-240's and is unchanged. Largest correctness surface is the
aggregation/floor layer, which is fixture-tested; largest drift surface is a
second committed artifact per group, bounded by the same
regenerate-on-conflict rule ADR-235 already imposes on the manifests.

No other domain's Assessment Question matches: no user-facing surface
(Product/UI — mechanical glob scan of Files lists returns zero matches), no
regulated-data surface (Legal), no vendor/procurement (Operations/Finance),
no pipeline or support surface (Sales/Support), no public messaging
(Marketing).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (87 open) for each
Files-to-Edit/Create path and the `regenerate-shard-manifest` /
`suite-shard-legs` / `suite-durations` tokens: two hits, both mentioning
`scripts/test-all.sh` without owning it —

- #8659 (test-helpers composed-EXIT-trap leak): **acknowledge** — scoped to
  `plugins/soleur/test/test-helpers.sh` trap semantics; this plan's single
  `run_suite` registration line does not touch trap machinery.
- #7942 (`*.mutation.sh` batteries run in no gate): **acknowledge** — naming/
  glob-coverage issue; no file overlap.

## Success Metrics

- Post-regen light-leg predicted totals within ~2× of the mean (vs measured
  5.4–18.8 min on run 36622402829); worst `test-scripts` leg back to the
  ~9–10 min band the K=7 matrix was sized for.
- The 12 currently-untabled registered labels carry real weight after the
  first regen under the new generator.
- `ci-leg-balance-9232` soak probe PASSes on ≥3 qualifying post-merge runs.
- `#8231` can pack the committed durations at any W with zero `gh` calls.

## Dependencies & Risks

- **Risk — artifact fetches at regen time grow** (~N runs × ~7–10 artifacts).
  Mitigation: bounded `per_page`, small zips (~KB each), manual cadence only.
- **Risk — `gh` availability at work time for the committed regen.** The PR
  regenerates the three manifests + durations tables from live main runs;
  if `gh` auth were unavailable the all-floor degrade still produces valid
  artifacts (and the dry-run evidence AC would then be marked accordingly).
- **Risk — generated-artifact conflicts** (ADR-235): a sibling PR
  regenerating the same manifests will conflict. Mitigation: documented
  resolve-by-regen rule (runbook update names it); sorted rows keep the diff
  region small.
- **Risk — floor weight misestimates a genuinely heavy new suite.** Bounded:
  floor = median-of-measured is conservative middling weight, and one regen
  after the suite's first timed run replaces it with the measured value.
  Self-correcting is the design goal.
- **Dependency — #8231's scheduler** consumes `--legs`/`--durations`; the
  shared-resource serialization constraint (#8163) is that issue's scope.
  This plan posts a consumption-contract pointer comment on #8231 so the
  dependency is recorded both directions.
- **Constraint — the `_shard_selects`/manifest parse contract is pinned
  unchanged** (AC): a 2-column `label<TAB>leg` row format, `# n=` header,
  and the existing override/fallback env seams.

## Implementation Phases

### Phase 1 — battery rows first (RED)

1.1 Extend `plugins/soleur/test/regenerate-shard-manifest.test.sh` with the
fixtures J–M + floor/second-member/dispatch rows listed in Guard Contract 1
(cq-write-failing-tests-before); bump `MIN_CASES` in the same edit — expected
RED until Phase 2 lands.
1.2 Extend `plugins/soleur/test/scripts-shard-manifest.test.sh` and
`.github/scripts/test/test-infra-suite-registration.sh` with the
durations-table blocks (Guard Contract 2); bump `MIN_CASES`.

### Phase 2 — generator implementation (GREEN)

2.1 Input layer: `green_main_runs()`, `--runs N`, repeatable `--timings-dir`,
`--durations`/`--durations-out`, source-precedence chain
(`--durations` > `--timings-dir` > gh) with honest provenance per `main()`'s
pairing rule; `expected_legs` WARN stays bound to the workflow's declared N.
2.2 Aggregation + floor: per-label median across runs, `floor_ms` derivation,
`src` provenance, all-floor WARN-degrade.
2.3 Emission: `--legs K`, default-path n-mismatch refusal, durations-table
writer, `GENERATOR_VERSION` → `"3"`, header/report fields.
2.4 Re-run the batteries to GREEN.

### Phase 3 — regenerated artifacts + docs

3.1 Regenerate all three manifests + durations tables against the latest
green main runs; paste the dry-run predicted-leg table into PR evidence.
3.2 ci.yml comment refresh; runbook update (regen procedure + #8231 recipe +
resolve-by-regen conflict rule).
3.3 ADR-240 amendment (see below); post the consumption-contract pointer
comment on #8231.

### Phase 4 — soak probe

4.1 `scripts/followthroughs/ci-leg-balance-9232.sh` + `.test.sh` + the one
`run_suite` registration; probe exits per the sweeper contract.

### Phase 5 — end-to-end verification

5.1 The `--enumerate` consumption check under `SCRIPTS_SHARD=k/4` +
`SOLEUR_SHARD_MANIFEST` for all four legs.
5.2 Full touched-shard run + markdownlint on all touched `.md` files.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Re-implement positional→LPT "duration-aware" packing as the issue's letter describes | **Rejected — already shipped.** Sticky-LPT exists (ADR-240); the residual gaps are aggregation horizon, floor weights, and K-flexibility. |
| Embed durations as `#`-comment rows inside the manifest itself | **Rejected — opaque.** The runner skips comments, but hiding a second data plane inside the artifact makes the file's contract muddier than a sibling table, and conflates the machine-written payload with human-authored comments. |
| Local scheduler re-fetches CI artifacts via `gh` at dispatch | **Rejected — wrong dependency.** A dev-host test run should not need ~50 artifact downloads or auth mid-run; the committed durations table makes the pack offline-deterministic. |
| `max` (or p90) cross-run aggregation | **Rejected — spike-pinning.** #8163 measured one suite at 2.4× under sibling contention; max would entrench contention into the table. Median requires a sustained shift. |
| Auto-refresh workflow regenerating manifests on schedule | **Rejected — ADR-240 decision 5 already ruled.** Manual named refresh + drift detection; the followthrough probe supplies the detection half this issue adds. |
| Tighten the ⊆ lint to bidirectional (registered ⊆ manifest) | **Rejected — conflict magnet.** Every suite-adding PR would be forced to regenerate and conflict on the artifact; hash fallback exists precisely to absorb post-regen additions. |

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`
in this PR — a dated amendment recording: (a) inputs aggregate across the
last N green runs by median, (b) untimed registered labels pack at a
documented floor weight, (c) the generator emits at arbitrary K (`--legs`)
with a refused commit-time n-mismatch, and (d) the aggregated
`suite-durations-*.tsv` tables are committed ADR-235 artifacts — the single
duration source for CI regen and the #8231 local scheduler. No new ADR: this
extends one existing decision, not a new boundary.

### C4 views

**No C4 impact.** Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`)
against the rubric: (a) external actors — only the operator/founder
interacts, already modeled; (b) external systems — the generator's `gh api`
calls ride the existing `github` system and its edges; no new vendor; (c)
containers/data stores — committed TSVs are files in the repo tree, not a
modeled store (the `kb` element covers committed content at this
granularity); (d) access relationships — none change. CI shard machinery is
not a modeled element today and this change adds none.

### Sequencing

The ADR-240 amendment lands in the same commit as the generator change — the
decision and its mechanism ship together.

## Research Insights

**Premise Validation (Phase 0.6).** Checked and held: #9232 OPEN; #8231,
#8881, #8163, #7454 all OPEN; `scripts/regenerate-shard-manifest.py`,
`scripts/test-all.sh`, both manifests, and the ci.yml matrix block exist on
this branch and match origin/main. **Stale:** the issue's "positional
slicing" framing — the manifest path has been duration-aware sticky-LPT since
ADR-240 shipped (2026-09-23); and "the existing timing floor" — no floor
exists (verified: untimed labels are not tabled; zero timings is a `die`).
**Also measured this session:** run 36622402829 per-leg suite-time totals
(light: 9.0/10.9/18.8/9.6/5.4/9.2/9.8 min; heavy: 5.9/7.2/1.2 min), leg 3's
top weights (test-all-affected 384 s, lint-orphan-test-suites-mutations-a
327 s, test-contention 135 s), 518 registered vs 506 tabled labels, manifest
provenance `generated-from-run=36125573947` (2026-09-25).

**Property List (Phase 0.6b).** (a) Leg assignment reflects measured cost —
already bought by ADR-240's sticky-LPT; (b) balance robust to single-run
staleness — last-N aggregation; (c) every registered suite carries weight —
floor tabling; (d) the packing is consumable at arbitrary K offline —
`--legs` + committed durations; (e) graceful degrade on missing history —
floor/all-floor path; (f) self-correcting as suites drift — the same regen
that consumes new timings produces the refreshed table.

**Cut List.** "LPT bin-packing" as a new mechanism → property (a) → already
covered by `assign()`. A committed *W*-grouped artifact → property (d) is
better served by committed *weights* + re-pack (W is host-dependent; a
committed grouping at one W serves no other). A bidirectional manifest lint →
no property in the list, and conflicts with insertion-stability — cut
(Alternatives table records it).

**Value-Proposition Measurement (0.6c).** The claimed saving is CI wall-clock
on the worst leg: measured baseline above (18.8 min suite time vs ~9.5 min
siblings on run 36622402829; command: `gh api
repos/jikig-ai/soleur/actions/runs/36622402829/artifacts?per_page=100` +
per-artifact `suite-timings.tsv` sum). The mechanism that buys it is
weight-accurate packing, which is exactly what last-N + floor add.

**Repo anchors.** `scripts/regenerate-shard-manifest.py` (`assign`,
`merge_tsv`, `fetch_timings_from_run`, `read_ci_leg_count`,
`registered_labels`, `render`, `main`, `GENERATOR_VERSION`,
`EPSILON_FRACTION`); `scripts/test-all.sh` (`_shard_selects`, manifest loader
block, `SOLEUR_SHARD_MANIFEST{,_HEAVY}` seams, `unset SCRIPTS_SHARD`
post-parse, `run_suite` chokepoint, followthrough `run_suite` block ~4042);
`.github/workflows/ci.yml` (test-scripts matrix + stale guidance ~1029–1044,
timing-artifact uploads ~1201/1290); `plugins/soleur/test/
regenerate-shard-manifest.test.sh` (`gen()` seam, `MIN_CASES`),
`scripts-shard-manifest.test.sh` (⊆ lint, n-pin, `MIN_CASES`),
`scripts-shard-totality.test.sh` (mechanism-agnostic union check);
`.github/scripts/test/test-infra-suite-registration.sh` (infra manifest
coherence ~283–320); `apps/web-platform/infra/run-registered-suites.sh`
(`SOLEUR_INFRA_*` seams); `knowledge-base/engineering/operations/runbooks/
ci-test-scripts-sharding.md`; `scripts/followthroughs/
deploy-script-tests-legs-8736.sh` (soak-probe precedent + exit contract).

**Institutional learnings applied.**
`2026-09-25-matrix-k-cannot-split-an-atomic-suite.md` (the AC's mega-suite
carve-out; regenerate-and-read-the-predicted-table before judging K);
`2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`
(ADR-235 — sorted deterministic rows, regen-on-conflict, applied to the new
durations tables); `2026-09-26-ci-orphan-suite-rows-split-brainstorm.md`
(the -a/-b split that explains the untabled-heavy-suite class);
#8006's own deferred analysis (the sticky-LPT + offline-manifest mechanism
this extends; its soak-probe `ci-leg-durations-8006.sh` — retired with its
tracker — shapes the followthrough here, and
`deploy-script-tests-legs-8736.sh` supplies the live precedent for the probe's
exit contract and retirement comment). Deepen-round additions:
`2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md` (five
precondition-drift findings killed a prior CI-shard plan — the reason every
count and flag name above is measured, not assumed);
`2026-08-06-read-the-generated-artifact-not-the-generators-spec.md` (the
dry-run-evidence AC reads the produced tables, never the flag spec);
`2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md`
(the `--write` refusal exits 2 BEFORE writing — the exit code + stderr line
IS the refusal artifact; nothing partial is committed);
`2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md` (the
touched-shard run in Phase 5 derives its suite set from `git grep` over the
changed files' consumers, not from memory).

**CLAUDE.md conventions.** Constitution: fail-closed over fail-open (the
`--write` n-mismatch refusal), generated artifacts get deterministic sorted
output and provenance, suite extensions live in the existing `*.test.sh`
battery (no new suite file → no orphan-registration churn). Glossary: "shard"
used in its registered-slice sense (a `TEST_GROUP` partitioned by
`SCRIPTS_SHARD=k/N`); "leg" = one k/N slice.

**Related issues/PRs.** #8231 (consumer — local parallel scheduler; PR #8270
merged only the green-baseline precondition, scheduler still open), #8881
(K=6→7 manual rebalance this replaces), #8163 (shared-resource serialization
constraint for the local consumer), #7454 (umbrella), #8006/ADR-238/ADR-240
(the mechanism's provenance), PR #9233 (this branch's WIP PR).

## Sharp Edges

- A plan whose `## User-Brand Impact` is missing/placeholder fails
  deepen-plan 4.6 — filled above (`threshold: none` + the scope-out bullet,
  since `apps/web-platform/infra/suite-durations.tsv` matches the
  sensitive-path regex `apps/[^/]+/infra/`).
- The `discoverability_test.command` above is Check-10-clean: allowlisted
  verb `python3`, no `|;&<>$\`` metacharacters, finishes in <15 s, and
  `expected_output` is a literal stdout substring, not a description.
- The new flags' spellings are prescribed, not assumed — none exist today
  (verified `grep -rn -- '--legs\|--runs\|--durations' scripts/` → zero).
- AC "this PR does not touch X" uses `origin/main...HEAD` merge-base diff,
  not tip diff (sibling merges must not redden it).
- Keep `assign()`'s sticky-LPT incumbent logic — the committed manifest must
  stay minimally-diffed on each regen (ADR-235); do not "simplify" to plain
  LPT.
- The `# generated-from-runs` header must not break `scripts-shard-
  manifest.test.sh`'s `^# generated-from-run` grep — verified prefix-safe;
  write BOTH keys anyway.
- markdownlint runs on this plan + tasks.md before hand-off; no literal TABs
  inside quoted commands (all TSV shapes written as `label<TAB>ms` prose,
  never literal tabs).

## References & Research

- Issue: #9232; evidence run 36622402829 (job 109590824903); artifact names
  verified live (`suite-timings-scripts-0..6`, `suite-timings-scripts-heavy-0..2`).
- Decisions: ADR-240 (mechanism + refresh contract), ADR-238 (rejected
  runtime LPT — the chokepoint can't compute), ADR-235 (generated-artifact
  discipline), ADR-193 (battery accounting/`MIN_CASES`).
- Precedents: `scripts/followthroughs/deploy-script-tests-legs-8736.sh`
  (soak-probe shape + exit contract + retirement comment),
  `scripts/followthroughs/` convention + `scheduled-followthrough-sweeper.yml`.
- No external documentation needed — all mechanics are repo-internal;
  Phase 1.6 external research deliberately skipped (strong local context).

**Deepen-plan round (2026-09-29, inline — no spawn-capable tool in this
harness).** Gate ledger: 4.4 precedent-diff — the committed-artifact header
shape follows ADR-235's canonical form (the manifest's own `#`-comment
provenance block is the precedent, mirrored by the durations tables); the
file-write precedent is `main()`'s plain `open(path, "w")` (~line 360) — no
`os.replace`/fsync precedent exists in `scripts/*.py` (verified by grep), so
the durations writer mirrors the manifest writer and torn writes are caught
by the same lint the manifests already face; the soak-probe precedent is
`deploy-script-tests-legs-8736.sh` (exit contract copied verbatim). The
scheduled-work check does not fire — the followthrough rides the existing
`sweep-followthroughs` infrastructure, no new trigger. 4.45
verify-the-negative — re-probed: "no timing floor" → `grep -n 'floor|DEFAULT'
scripts/regenerate-shard-manifest.py` returns zero; "untabled labels
hash-fall" → `_shard_selects`'s manifest-miss arm is the `cksum` path;
"MIN_CASES=20/25" verified at the named anchors; `latest_green_main_run`
exists at line 88 (multi-run sibling `green_main_runs` is a NEW symbol —
the plan says so); `ci-leg-durations-8006.sh` is absent under
`scripts/followthroughs/` — re-marked retired, live precedent named instead.
Post-edit self-audit: the only dropped claim was mutual-exclusion →
precedence; every other occurrence was swept (Proposed Solution + tasks.md
both updated). 4.5 network-outage — zero trigger-pattern matches in
Overview/Problem sections (grep rc=1). 4.55 downtime — no serving surface,
no reboot/DDL/router class in the Files lists. 4.6 PASS — section present,
threshold `none`, sensitive-path matches enumerated as the two
`apps/web-platform/infra/*.tsv` paths and covered by the scope-out bullet.
4.7 PASS — all five fields populated, non-placeholder; probe verb `python3`
is Check-10-allowlisted, no SSH, `--help` returns in <1 s,
`expected_output: durations` is a literal. 4.8 PAT sweep clean (the
`secrets=GH_TOKEN` directive token is a sweeper contract name, not a
PAT-shaped variable or literal). 4.9 no UI surface — the Files lists match
zero globs in `ui-surface-terms.md`. 4.10 no store class or new connection —
committed TSVs are not a volume/bucket/queue and `gh api` is an existing
call pattern. 4.11 `python3 scripts/lint-guard-contract.py` → green, 2 guard
entries; adequacy read: Guard 1's assembly is the generator pipeline +
chokepoint (`assign()`), not a member list; Guard 2's assembly binds to the
registered-set enumeration, not a name list; both matrices carry a
dispatch/vacuity row and a second-member or must-PASS row. Quality checks:
flag spellings (`--runs`/`--legs`/`--durations`/`--durations-out`) and
artifact names (`suite-durations{,-heavy}.tsv`,
`apps/web-platform/infra/suite-durations.tsv`, `ci-leg-balance-9232`)
grep-verified consistent across Proposed Solution, Guard Contract, ACs, Test
Scenarios, and tasks.md; rule-id citations (`cq-test-fixtures-synthesized-
only`, `cq-write-failing-tests-before`, `hr-observability-as-plan-quality-
gate`) verified live in AGENTS.md.
