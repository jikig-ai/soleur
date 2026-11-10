---
title: "ci: bound the ci-push-dedupe-soak-9512 read window (Epic #11556 Lever A)"
type: fix
date: 2026-11-10
slug: ci-soak-read-window-bound
branch: feat-one-shot-12017-soak-read-window
issue: 12017
closes: 12017
domain: engineering
brand_survival_threshold: none
---

# ci: bound the ci-push-dedupe-soak-9512 read window (Epic #11556 Lever A)

## Overview

#12017 (Epic #11556 Lever A): the `scripts/followthroughs/ci-push-dedupe-soak-9512` suite measures
254.6s median on green `merge_group` runs against a committed price of 87.9s (+190%), and the
production probe itself is one of the four soak probes named in `scripts/sweep-followthroughs.sh:58`
as taking 1.5–5 minutes per sweep (the reason `FT_PROBE_TIMEOUT=300` exists, CTO ruling Ref #11215).
The suite pays ~420 probe invocations (70 contract rows, ~100 mutant named-row re-runs, three
`ALL_ROWS` harness controls, inner loops), and inside the probe every sampled run costs a `date`
call, four separate `jq` evaluations, and (per elided run) a voucher `jq`; the `merge_group` voucher
listing follows `--paginate` to exhaustion. Bound the read work on both surfaces: batch the per-run
jq evaluations into one verbatim-subexpression program, emit the run epoch in the initial slice,
compute vouchers in a single post-loop pass, and replace unbounded `--paginate` with the repo's
established bounded page loop. On the suite side, memoize `build_fx` by fixture signature and bound
the three `ALL_ROWS` controls to a named `CONTROL_ROWS` subset, then re-price
`scripts/suite-durations.tsv`.

## Research Insights

### Premise Validation

- `gh issue view 12017` → OPEN, `"ci: soak suites rising 160-190% vs price — bound the read window"`,
  `closedByPullRequestsReferences: []`. `gh issue view 11556` → OPEN epic.
- `git log -1 f88359a7f8` → real; it retired sibling `ci-draft-light-soak-9728.sh` (confirmed absent
  in this worktree — out of scope per the brief).
- `git show origin/main:scripts/followthroughs/ci-push-dedupe-soak-9512.sh` → present (270 lines).
- `bash scripts/collision-precheck.sh 12017` → PR #12622 is this branch's own WIP draft (empty
  files list — not a foreign duplicate); `test-all.sh` processes in five other worktrees are
  other pipelines' runs (informational).
- ADR corpus check on the proposed mechanism: `grep ADR-276` → the S2 amendment pins the soak's
  statistical contract — "the daily soak probe measures the trailing sample of at most 100 push
  runs, about 4 days" (`knowledge-base/engineering/architecture/decisions/ADR-276-*.md`, amendment
  2026-10-09 Decision 3(e)). MAX_RUNS=100 is contractual; shrinking it or adding a day-bound would
  amend ADR-276, which this plan does not do.

### Property List

1. Suite wall time returns to ~committed price (the measured +190% regresses toward 0).
2. No unbounded read remains in the probe (the only unbounded one today is `api --paginate` over
   `merge_group` runs, bounded only implicitly by the anchored window).
3. Probe verdict semantics are unchanged — this is the live exit/detect gate for ADR-276 S2
   (wrong elision, early elision, mean-over-target, failing dedupe, deadline, deregistration).
4. The mutation battery keeps its kills (every re-anchored mutant still turns its named rows red;
   `MUT_RUN`/`MUT_CAUGHT` equality and floors hold).
5. Production sweep latency drops (the probe is on the `sweep-followthroughs.sh` daily path with a
   300s per-probe kill cap it has already approached — Ref #11215).

### Cut List

- "Bound to last N runs/days" on the push-run window — cut: `MAX_RUNS=100`/`IDLE_RUNS=10` already
  bound it, and a day-bound would amend the ADR-276 S2 contract (property P3). The issue's "or"
  alternative — "paginate to a cap" — is what survives for the merge_group read.
- Shrinking fixture run-counts row by row — cut: ~25 runs is near the coverage floor
  (MIN_ELIDED=10 elided + full runs holding the mean over/under); r_max_cap's 70 can drop to 40
  without weakening its property (distinguishes a MAX_RUNS=30 mutant) and is folded into the
  memoization change as a one-token edit.
- Splitting the suite into two registered legs — cut: halves each leg's wall clock but doubles
  process overhead and raises total job-minutes (the epic's currency); the label/leg topology is
  owned by `scripts/test-all.sh` + `suite-shard-legs.tsv`, not this plan.

### Measurements (Phase 0.6c)

Command (micro-bench, extracted functions from the suite itself):

```bash
sed -n '1,100p' scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh > bench.sh
sed -n '126,264p' scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh >> bench.sh
# + PROBE=abs path, then: time build_fx … ; time expect …
```

Local results (this host is contended — five foreign `test-all.sh` runs; ratios, not absolutes,
carry the finding): `build_fx` (25-run fixture) ~0.33s; probe run on it ~1.6s; 70-run fixture
build ~1.0s, probe run ~4.1s. Per-row cost is ~80% probe loop, ~48ms per sampled run ≈ 6–7
subprocesses (`date` + `gh` stub + 4 `jq` + voucher `jq`). At CI speed the measured 254.6s across
~420 invocations is ~0.6s per invocation — consistent.

Row-execution census (from the suite source): 70 `ALL_ROWS` + ~15 inline `build_fx`/`expect` +
`r_markers` (10 inner probe runs) + `r_needtools` (8) + ~100 mutant named-row re-runs + three
`ALL_ROWS` harness controls (210) + ~8 misc = **~420 probe invocations**. The three controls alone
are ~half of all invocations.

### Learnings / precedent

- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` — the fake `gh` whitelists real flags and
  refuses invented ones; adding `&page=$p` reads must be modeled in the stub, not answered
  blindly.
- `2026-11-08-mutant-killability-and-fixture-key-scoping.md` — a mutant row is real only if the
  mutant is killable by construction: replacement text must leave executable code, and fixture
  keys are computed at bind time. Both constrain the re-anchoring and the `build_fx` memoization
  key (signature must cover every arg, including `fail*` touch-file flags).
- PR #12419 (`404e4c626f`, feat-one-shot-ci-replay-b-pacer) — sibling epic slice with the same
  shape: measure the pristine site first, bound the runaway while preserving kills, then re-price
  the durations tsv and bump the assertion floor honestly.
- Bounded-pagination precedent in-repo: `scripts/followthroughs/pr-battery-gate-saving-9323.sh:242`
  (`api "...&page=$p"`), `scripts/followthroughs/cron-machinery-soak-9272.sh:136` (`for page in 1
  2 3 4 5` + early-exit). The plan mirrors this shape.
- `2026-10-22-a-probe-went-blind-...md` — pin emitters by value; the new exhaustion path gets its
  own literal + row rather than reusing a generic CANNOT ESTABLISH string.

### Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the four touched
paths.

## Problem Statement / Motivation

The suite's committed price (87.9s, `scripts/suite-durations.tsv:427`) was set when the probe loop
and the row/mutant census were smaller. The audit
(`knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` row 11) prices it at
254.6s median — +190% — class "soak-probe loop over dedupe units". Two growth mechanisms:

1. **Per-invocation cost** — each sampled run in the probe loop spawns ~6–7 subprocesses; the
   suite drives ~420 probe invocations per CI run, so subprocess fan-out dominates wall time.
2. **Re-enumeration** — mutants re-run named rows (each re-builds its fixture dir and re-runs the
   probe), and three harness controls each re-run all 70 rows. The read "window" the suite pays is
   effectively unbounded re-enumeration.

In production the same probe enumerates up to 100 runs per sweep serially (~1.5–5 min observed)
and follows `--paginate` on the voucher listing — the only read in the script with no explicit
bound.

## Proposed Solution

**Probe (`scripts/followthroughs/ci-push-dedupe-soak-9512.sh`):**

- Merge the four per-run `jq` evaluations (`is_elided`, `pd_failed`, `proof_holds`, `secs`) into
  ONE jq invocation emitting a `@tsv` line: `[(<P1>),(<P2>),(<P3>),(<P4>)] | @tsv`, where each Pi
  is the *existing program copied verbatim inside parens* — every mutation anchor that targets a
  jq subexpression survives byte-identical (the mutant harness asserts `s.count(old) == 1`).
  Bash splits on tab.
- Emit `created_epoch` in the existing runs slice (`(.created_at | fromdateiso8601)` as a 4th TSV
  field); drop the per-run `date` call. An unparseable `created_at` then fails the slice jq →
  `fail_api "ci.yml push runs"` (still rc 3; no row asserts the per-run variant of the message).
- Replace the per-elided-run voucher `jq` with a single post-loop pass: collect elided
  `{id, sha}` pairs in a bash array, then one `jq` diffs them against `mg_json`'s sha set and
  emits `run=<id> sha=<prefix>` lines for the unvouched → `wrong` count + `wrong_list` unchanged.
- Bound the `merge_group` read: replace `api --paginate` with `for page in 1..MG_MAX_PAGES` using
  `&page=$p` (mirroring `pr-battery-gate-saving-9323.sh:242`), accumulate until a page returns
  fewer than 100 runs. `MG_MAX_PAGES=10` (≈1000 runs ≈ ~40 days of merges; the anchored window is
  volume-correlated to the ≤100-run push sample so ~2 pages is typical). If the final fetched
  page is full (enumeration possibly truncated) → `CANNOT ESTABLISH` naming the cap (rc 3: the
  sweeper retries; it never silently degrades vouchers into a wrong-elision FAIL).

**Suite (`scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`):**

- Fake `gh` models `&page=$p` for the `merge_group` endpoint: serves `mg-N.json` for page N,
  `{"workflow_runs":[]}` beyond the fixture's page count, and refuses a `merge_group` read with no
  `page=` (the paginate-arm assert is replaced by a page-param assert — stub fidelity per the
  2026-09-25 learning). New `mgpages=K` fixture flag writes K full synthetic pages to exercise the
  exhaustion arm.
- `build_fx` memoization: `declare -A FX_SEEN`, key `"$fx|$*"` (fixture dir + every arg verbatim);
  on a hit, `rm -f "$fx/requests.log" "$fx/refused.log"` and return — the only per-run mutable
  state inside a fixture dir is those two logs (fail-* markers, comments, and job JSONs are all
  fixed by the signature). Mutant re-runs and the three controls then skip the rebuild.
- `r_max_cap` fixture 60→40 full runs (still > the m-max-cap mutant's MAX_RUNS=30; property
  unchanged).
- `CONTROL_ROWS` subset for the three `ALL_ROWS` harness controls (identity copy, no-lib copy,
  always-PASS probe): a named list covering every verdict class and machinery arm —
  `r_pass r_unmatched1 r_unmatched3 r_over r_nomarker r_zero r_jobsfail r_noperm_act
  r_adr_proposed r_unregistered r_deact r_needcomplete` (12 rows: rc 0/1/2/3, voucher, mean,
  marker, trust-permission, ADR, registration, lib-presence). The always-PASS floor recomputes
  to ≥10 of 12 red — `r_pass` and `r_needcomplete` are red-immune by construction (an
  always-PASS probe emits rc=0 + "PASS", and both rows' expectations are exactly that shape;
  every other CONTROL_ROW expects a distinct verdict or detailed output string). The
  CONTROL_ROWS comment in the suite records the two survivors and why, so a future edit to
  either row's expectation re-tallies the floor.

**Re-price:** `python3 scripts/regenerate-shard-manifest.py --incremental --write` (or a targeted
row update if the incremental pass touches unrelated rows — convention per PR #12419: commit the
measured value and name the runs it was measured over).

## Technical Considerations

- **Anchor preservation rule.** Any probe text a `mutant` anchors on must either survive
  byte-identical or be re-anchored in the same diff — `s.count(old) != 1` turns the mutant into
  "did NOT land" (a suite FAIL, loud but blocking). Mutants needing re-anchors under this design:
  `m-unmatched-ok`, `m-no-voucher` (voucher mechanism moves post-loop), plus any whose anchor
  spans lines being restructured — enumerate by running the suite; `MUTANTS: N of N caught` and
  the floor (`MUT_RUN -ge 67`, assertion `_FLOOR=176`) are the proof.
- **The probe is a live safety gate.** Every exit-code path (0/1/2/3/78) must survive; the suite
  exists precisely to pin it. No new `exit` site may bypass the precedence order (FAIL checks
  before NOT YET).
- **Fake `gh` argv-strictness.** The page-loop changes `api` argv shape; the stub's endpoint
  glob and flag whitelist must accept `&page=$p` and keep refusing anything else.
- **`r_needcomplete`/`r_needtools`** pin the probe's external-command census — the redesign adds
  no new tool (`grep`, `sort` already declared); if a new external command appears, both rows
  catch it (and the need list must grow in the same diff).
- **NFR impacts:** CI runner cost (primary), probe reliability under sweep timeout (secondary).

## Files to Edit

- `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` — merged per-run jq, epoch-in-slice,
  post-loop voucher pass, bounded `&page=$p` merge_group loop (MG_MAX_PAGES=10), CANNOT
  ESTABLISH exhaustion message.
- `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` — fake-gh page model + `mgpages=K`
  flag, `build_fx` memoization, `CONTROL_ROWS` subset for the three controls, re-anchored
  mutants, new rows (`r_mgcap` exhaustion → rc 3; a cap-not-fail-closed mutation row), updated
  always-PASS floor + comment.
- `scripts/suite-durations.tsv` — re-priced row for this suite (via the regenerator or targeted
  edit per PR #12419 convention).

## Files to Create

None. (Plan artifacts under `knowledge-base/project/specs/feat-one-shot-12017-soak-read-window/`
are pipeline bookkeeping, not product files.)

## Implementation Phases

**Phase 1 — suite-side bounds (probe untouched).** `build_fx` memoization + `CONTROL_ROWS`
subset + `r_max_cap` 60→40 + updated floors/comments. The suite must pass with the probe
unmodified — this isolates the harness-side saving (measure: `time bash
scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`).

**Phase 2 — probe loop batching.** Merged per-run jq (verbatim subexpressions), epoch-in-slice,
post-loop voucher pass, the two voucher-mutant re-anchors. Semantics pinned by the unchanged
rows; kill-count parity is the AC.

**Phase 3 — bounded merge_group enumeration.** `&page=$p` loop + MG_MAX_PAGES=10 + exhaustion →
rc 3; fake-gh page model; `mgpages=K` flag; `r_mgcap` row; `m-mg-cap-silent` mutant (dropping
the exhaustion check must turn `r_mgcap` red). Requests-log assertion updated for the new argv
shape (it still greps `created=%3E<iso>` — the substring precedes `&page=`).

**Phase 4 — measure + re-price.** Run the suite (target ~≤110s CI-class); then
`python3 scripts/regenerate-shard-manifest.py` re-price of the suite-durations row naming the
green `merge_group` runs measured, or targeted row edit documenting the measurement. Commit
message records local + CI medians.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the blast radius is a
  follow-through soak probe for an internal CI cost lever; a false verdict would post FAIL/NOT
  YET on an internal tracker (#9512's follow-through issue), and a slower suite would only
  lengthen our own CI.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the script reads public-shape GitHub Actions metadata with the sweeper's `GH_TOKEN` and writes
  nothing user-visible.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches only internal CI-cost tooling — a
  probe script, its test harness, and a generated durations table — with no user-facing surface,
  so the next tier's "one user's breach" framing has no object.

## Observability

```yaml
liveness_signal:
  what:            the probe's daily verdict line (`activated=… trailing_push_runs=… mean_job_min_per_run=…`) emitted by the scheduled follow-through sweeper
  cadence:         daily (sweep-followthroughs.sh)
  alert_target:    follow-through tracker issue (#9512's tracker) — FAIL/NOT YET verdicts surface there
  configured_in:   .github/workflows/scheduled-followthrough-sweeper.yml + scripts/sweep-followthroughs.sh
error_reporting:
  destination:     the tracker issue + sweeper job log
  fail_loud:       exit 1 FAIL / exit 3 CANNOT ESTABLISH (retried) / FT_PROBE_TIMEOUT kill reported as CANNOT ESTABLISH with the script name
failure_modes:
  - mode:          voucher enumeration exceeds MG_MAX_PAGES
    detection:     in-probe exit 3 with a distinct 'merge_group' cap message (asserted by r_mgcap)
    alert_route:   tracker + sweeper log
  - mode:          probe slows past the per-probe sweep cap
    detection:     FT_PROBE_TIMEOUT kill → CANNOT ESTABLISH naming the script (sweep-followthroughs.sh:62)
    alert_route:   tracker + sweeper log
  - mode:          suite regresses past committed price again
    detection:     suite-durations.tsv committed price vs the shard-balance watch's price-vs-measure drift check
    alert_route:   wallclock-p90-watch report (scripts/watch-wallclock-p90-11774.sh)
logs:
  where:           sweeper workflow run log + suite-timings artifact on merge_group runs
  retention:       Actions log retention / suite-timings 14 days
discoverability_test:
  command:         grep -c 'ci-push-dedupe-soak-9512' scripts/test-all.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1 — bounded merge_group enumeration

**Property.** Every `merge_group` voucher read stops after at most MG_MAX_PAGES requests, and an
enumeration that may have been truncated reports CANNOT ESTABLISH rather than emitting a verdict
on a partial voucher set.

**Assembly.** The single read site — the `merge_group` runs listing in
`scripts/followthroughs/ci-push-dedupe-soak-9512.sh` (one chokepoint: all voucher evidence flows
through `$mg_json`, produced only there). The fake `gh` in the suite is the only other surface
and refuses unmodeled argv.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `for page` bound so pagination follows exhaustion again | RED (shape/argv pin or `r_mgcap`) |
| 2 | Drop the exhaustion check (`< full page after cap`) so a truncated listing exits normally | RED (`m-mg-cap-silent` → `r_mgcap`) |
| 3 | Serve an 11th fixture page after 10 compliant ones (`mgpages=11`) | RED — `r_mgcap` asserts rc 3 at the cap |
| 4 | Mutant accepts `page=0` or drops `&page=` so the loop can stall | RED — stub refuses page-less/param-less mg reads |

### Guard 2 — verdict equivalence under batching

**Property.** The merged per-run jq program and post-loop voucher pass produce byte-identical
verdict semantics to the four separate evaluations — every exit-code path reachable before stays
reachable and ordered the same.

**Assembly.** The single per-run evaluation site inside the probe's `while read` loop plus the
post-loop voucher computation — both chokepoints all sampled runs flow through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Weaken any merged subexpression (`all`→`any` on test-scripts skipped) | RED (`m-ts-any` re-pinned inside the merged program) |
| 2 | Post-loop voucher pass that always returns empty unvouched list | RED (`m-no-voucher` re-anchored → `r_unmatched1`/`r_unmatched3`) |
| 3 | Harness-side: CONTROL_ROWS subset that excludes every rc-1 row — always-PASS floor can't be met | RED (floor assertion `≥10 of 12` fails on an rc0-only subset) |
| 4 | build_fx cache key that drops a signature component (e.g. `marker=` ignored) | RED — a marker-variant row serves the wrong fixture and contradicts its expected rc |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Bound the read window (last N runs/days) or paginate to a cap." [issue #12017] | Phase 3 (`&page=$p` + MG_MAX_PAGES); Phases 1–2 (enumeration bound) | mapped |
| 2 | "ci-draft-light-soak-9728 +162%, ci-push-dedupe-soak-9512 +190% vs committed price" [issue #12017 context] | Phase 4 re-price + suite-time AC | mapped |
| 3 | "Sibling ci-draft-light-soak-9728.sh was retired in commit f88359a7f8 and is out of scope" [brief] | — | descoped — justification: retired upstream; nothing to bound |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ci-push-dedupe-soak-9512.sh` edits | "bound the read window in `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`" [brief] | asked |
| `ci-push-dedupe-soak-9512.test.sh` edits | "soak probe enumerates/reads large run sets and cost grows with history" [issue #12017] — the cost measured is the suite's | inferred — justification: the +190% figure is a suite-time measurement (`suite-timings` artifact), so the suite's re-enumeration is in the priced unit |
| `suite-durations.tsv` re-price | "vs committed price" [issue #12017] — the price lives in this file | inferred — justification: a bound whose measured value is never committed leaves the drift metric stale (PR #12419 convention) |
| CONTROL_ROWS subset | — | inferred — justification: three `ALL_ROWS` controls are ~50% of invocations; bounding them is the largest single enumeration lever; coverage trade recorded as a technical ruling |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 3 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The probe's `merge_group` read issues at most MG_MAX_PAGES=10 `&page=$p` requests; an
  enumeration reaching the cap with a full last page exits 3 with a message naming the cap.
- [ ] Per sampled run the probe executes at most one `jq` evaluation plus the `gh` jobs read
  (measured: `bash -x`/`requests.log` + a process count, or a timing assertion — the suite's
  `expect` machinery proves the merged program via the unchanged rows).
- [ ] `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` exits 0: all rows pass,
  `MUTANTS: N of N caught` with N ≥ 67, assertion count ≥ the adjusted floor.
- [ ] Every mutation whose anchor moved under the rewrite is re-anchored and still turns its
  named rows red (no "did NOT land" / survivor beyond the deliberate equivalent-mutant control).
- [ ] `build_fx` rebuilds a fixture dir at most once per unique signature in a suite run (a
  counter or `set -x` spot check proves the memoization fires).
- [ ] The three harness controls run `CONTROL_ROWS` (12 named rows) instead of `ALL_ROWS`, with
  the always-PASS floor updated and the red-immune rows recorded in a comment.
- [ ] `scripts/suite-durations.tsv` carries a re-measured price for
  `scripts/followthroughs/ci-push-dedupe-soak-9512`, with the green `merge_group` run IDs named
  in the commit message.
- [ ] Suite wall time measured ≤ ~120s on the CI-class surface (local `time` on this host and/or
  the first green `merge_group` suite-timings artifact post-merge).
- [ ] No change to `MAX_RUNS`, `IDLE_RUNS`, `MIN_ELIDED`, `MIN_DAYS`, `DEADLINE_DAYS`, or the
  mean limit (ADR-276 S2 contract preserved verbatim).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI-cost tooling on `scripts/` surfaces only.

## Test Scenarios

- Given a fixture with `mgpages=11` full merge_group pages, when the probe enumerates vouchers,
  then it exits 3 naming the page cap (`r_mgcap`, unit).
- Given a mutant dropping the exhaustion check (`m-mg-cap-silent`), when `r_mgcap` runs against
  it, then the row turns red (unit/mutation).
- Given a `build_fx` call with an already-seen signature, when the row executes, then the fixture
  dir is reused with `requests.log`/`refused.log` reset and the verdict is identical (unit).
- Given the merged per-run jq program, when each jq-subexpression mutant (`m-ts-any`,
  `m-skipped-filter`, `m-runner-type`, `m-negdur`, `m-heavy-prefix`, `m-heavy-exact`,
  `m-step-name`) is applied, then its named rows still go red (unit/mutation).
- Given the post-loop voucher pass, when `m-no-voucher`/`m-unmatched-ok` apply, then
  `r_unmatched1`/`r_unmatched3` go red (unit/mutation).
- Given an unparseable `created_at` in a fixture run, when the slice jq runs, then the probe
  exits 3 (unit — new edge introduced by epoch-in-slice; add a fixture flag or cover via the
  existing fail-push arm if it already exercises it).
- Given the always-PASS harness control on `CONTROL_ROWS`, when it completes, then the red count
  meets the recomputed floor and the red-immune rows match the recorded comment (unit).

## Success Metrics

- `scripts/followthroughs/ci-push-dedupe-soak-9512` suite median ≤ ~120s on green `merge_group`
  suite-timings (vs 254.6s baseline; target ≥ 50% reduction, committed price 87.9s is the stretch).
- Production probe sweep time visibly below the 300s `FT_PROBE_TIMEOUT` ceiling it has approached.
- Zero change in probe verdicts on identical inputs (the suite is the oracle).

## Dependencies & Risks

- **Risk: mutant re-anchor misses.** Any anchor left referencing removed text fails "did NOT
  land" — loud but blocking; the suite catches it in the same diff. Mitigation: keep the four jq
  programs verbatim inside the merged call so jq-internal anchors never move.
- **Risk: memoization serves a stale fixture.** The key is `"$fx|$*"` — every arg including
  `fail*` flags is in the signature; the only post-build mutable state (`requests.log`,
  `refused.log`) is reset on hit. Rows that mutate fixtures after build (none today) would break
  the invariant — the build_fx comment must name it.
- **Risk: CONTROL_ROWS weakens a harness census.** The always-PASS census narrows from ≥76 rows
  to the subset; recorded as a technical ruling (assumed: subset) — see
  `decision-challenges.md`. The alternative keeps full-set controls and lands ~105s instead of
  ~75s.
- **Risk: `fromdateiso8601` on a bad `created_at` now fails the slice instead of the per-run
  read.** Verdict stays rc 3 either way; add the fixture edge row to keep it pinned.
- **Dependencies:** none external; `regenerate-shard-manifest.py` for the re-price.

## Alternative Approaches Considered

| Approach | Rejected because |
|----------|------------------|
| Worker-model parallel probe (mirror `pr-battery-gate-saving-9323.sh`'s `_pbg_w_*` fan-out) | ~4–6× loop speedup vs ~2.5×, but rewrites the safety-critical loop into wlog/replay machinery (~120 lines) and breaks far more mutant anchors. Held as fallback if Phase 2 misses target — technical ruling row. |
| Shrink MAX_RUNS / add a day-bound on the push window | Amends the ADR-276 S2 contract ("trailing sample of at most 100 push runs"); out of scope without an ADR amendment. |
| Split the suite into two registered legs | Cuts per-leg wall clock but raises total job-minutes; doesn't bound the read work, only relocates it. |
| Keep `api --paginate`, slice the result to a cap | Bounds items, not requests — the requests are the cost; a slice after exhaustion saves nothing. |
| Drop or thin the mutation battery | The battery is the safety net for editing a live gate (learning 2026-11-08: kills must stay killable by construction); removing rows trades coverage, not cost class. |

## References & Research

- Issue: #12017; epic #11556; ref report `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (row 11, finding 3)
- Probe: `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` (esp. lines 158–213, the sample loop)
- Suite: `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` (`build_fx` 126–251, `expect` 257–264, `ALL_ROWS` 415–420, mutants 460–578, controls 579–630)
- Precedent: `scripts/followthroughs/pr-battery-gate-saving-9323.sh:242`, `cron-machinery-soak-9272.sh:136`; PR #12419 (`404e4c626f`); sweeper cap `scripts/sweep-followthroughs.sh:58-66` (Ref #11215)
- Contract: `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` (S2 amendment, Decision 3(e))
- Learnings: `2026-09-25-gh-stub-must-mirror-real-cli-flags.md`, `2026-11-08-mutant-killability-and-fixture-key-scoping.md`
