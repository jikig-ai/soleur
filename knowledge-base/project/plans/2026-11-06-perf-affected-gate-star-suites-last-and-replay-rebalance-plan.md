---
title: "perf(tests): run the drain-barrier (*) suites last, then rebalance the replay arms"
date: 2026-11-06
slug: affected-gate-star-suites-last-and-replay-rebalance
branch: feat-one-shot-12231-star-suites-last
issue: 12231
type: perf
lane: cross-domain
---

Spec lacks a valid `lane:` (no spec.md on this branch) - defaulted to cross-domain (TR2 fail-closed). The domain sweep below found Engineering only.

## Overview

Resume of the local affected-test gate speed work (epic #12013, open until a measured run meets the 10-minute bar). The
replay-arms-first change (#12228, ADR-242 Decision 29) landed and measured one cold reading of the pinned diff at 2134 s wall
(pool phase 1882 s) against the 600 s bar. This plan covers the two levers its "known limits" named, in this order, each measured
against a clean control:

1. **`*` suites last (#12231).** A suite whose lane token is `*` launches only on an empty pool and, while queued, blocks every
   later registration (`skip_tok`/`any_q` in `_pj_fill`). In the measured treatment reading the one selected `*` suite
   (`scripts/test-all-capacity-signal`, 9 s) launched at +1863 s, only when the pool had drained to its longest live suite
   (`approval-guard1-mutation`, 666 s), and 50 suites with 962 slot-seconds of work then ran behind it. The pool carried 1227
   idle slot-seconds before that point. The fix parks `*` candidates in the scheduler until the drain, so registration position
   stops being a barrier while exclusivity, the verdict and the rendered order stay as they are.
2. **Replay arm rebalance, gated by a paper check.** The three `ci-pr-affected-replay-{a,b,c}` arms (`--rows 1-193/194-386/387-599`
   of 599 gated sites) pool at 1513 / 570 / 530 s. After lever 1 `replay-a` ends 33 s above the packing floor (pool-relative 1513
   vs 1546 s, sum of walls / 4), and the pool end is set by `approval-guard1-mutation` (ends +1611 s pool-relative), whose start is
   a queue-order effect. A rebalance can therefore only help by freeing slots earlier. A list-schedule what-if over the treatment
   reading (CTO, 2026-11-06) predicts an equal split is 78 s WORSE and the best of 7848 contiguous splits only 27 s better, so
   Phase 4.0 re-runs that what-if first and the per-site measurement, the re-split and the T2 reading happen only if it clears
   a 30 s gain. Otherwise the PR says "not landed, paper-negative" and the lever moves behind #12263 (start-first for the long
   suites), which is what makes it pay.

Neither lever can reach 600 s alone (the floor is about 1546 s of pool phase plus about 250 s of cold derive); the PR is
`Ref #12013`, `budget_seconds` is not touched, and the number is reported as measured whether or not it meets the criteria below.
Expected CI effect of lever 2 if it lands: the old first arm was also the CI long pole, so a more even split should help or be
neutral; CI leg pins do not move (labels unchanged).

## Research Reconciliation - Spec vs. Codebase

| Claim (issue #12231 / brief) | Reality (checked 2026-11-06 on `origin/main` 78fbd47b9a) | Plan response |
|---|---|---|
| `test-all-capacity-signal` registered "at about line 7383" | Now at the `run_suite "scripts/test-all-capacity-signal"` registration (about line 7418); the file moved | Cite the content anchor, never the line |
| "sits before about 45 suites" | 50 suites with 962 slot-seconds started after it in the treatment reading (`treatment.suites.tsv`, start >= 1863 s) | Use 50 / 962 |
| "pool drains to the longest live suite (up to 729 s)" | Treatment reading: `approval-guard1-mutation`, 666 s, +1197 to +1863 s; 729 s was an earlier reading | Quote the treatment figure |
| Criterion 1: the replay start-priority PR "has landed and its own three readings are posted" | Landed as #12228 with two readings (one control, one treatment) by the CTO's adaptive ruling | The control for this lever is a fresh control from THIS PR's base (criterion 3 asks for one anyway); record the deviation |
| Criterion 4: "the verdict and the rendered order are unchanged" | Render order is index order (`_pj_drain` loops `i < _pj_next`); a registration move would change it, scheduler parking cannot | CTO ruled scheduler parking (Q1) |
| Five `*` suites (brief names three) | SIX declared `*` overrides in `scripts/lib/test-suite-lanes.sh` (`grep -c '^lane_declare .* "\*"'` = 6): cf-tunnel-liveness-gate-mutations, orphan-process-reaper, orphan-process-reaper-mutations, test-all-capacity-signal, `apps/web-platform/infra/run-registered-suites.sh` (declined in the pinned diff; inner `xargs -P` pool), md-to-mrkdwn; plus any suite whose source is unreadable (derived `*`) | Census in Research Insights; AC12 full run must show all six green |
| The planning model "reproduces the measured pool phase within 1 percent" | True for the r1/r3 readings it was fitted to; on the treatment reading's walls it predicts 2497 s vs 1882 s measured | The model is a direction check only; no number from it is evidence or goes in the PR; the cold readings are |
| Brief: "the arms pool at 1513 / 570 / 530 s" | Confirmed (`treatment.suites.tsv`: 252 to 1765, 822, 782) | Phase 4 |

## Research Insights

**Premise Validation (Phase 0.6).** #12231 and #12013 are OPEN. PR #12261 is this branch's own draft. PR #12228 is merged
(`78fbd47b9a`). The pinned-diff commit `7af192071d` exists locally. The cited test files exist (the orphan reaper's mutation half is
the singular `orphan-process-reaper-mutation.test.sh`). `_pj_fill`, `_pj_drain` (one call, the line `_pj_drain` after the
registrations), `_pj_submit`, `_pj_launch` exist. ADR corpus grep (`drain barrier`, `backfill`, `_pj_fill`): only ADR-242 speaks to
the mechanism (Decision 29 names `*`-last as the next lever); nothing rejects it. Collision pre-check: three foreign `test-all.sh`
processes are live in other worktrees (`feat-one-shot-12089-congestion-relief`, `feat-one-shot-9927-host-replace-window-plan`); they
share the CPU with any reading taken now, so every reading records loadavg and foreign pids and aborts when they are bad.

**Property List (Phase 0.6b).** P1: a `*` suite never overlaps any other suite. P2: registration position of a `*` suite no longer
delays a non-`*` suite. P3: verdict blocks, `TEST_TIMING_LOG` rows and the terminal marker keep registration order. P4:
`SOLEUR_PJ_FIFO=1` reproduces strict FIFO. P5: suite set, labels and argv are unchanged by lever 1. P6: the three arms keep tiling
1..599 exactly once after a re-split. P7: both levers are credited only by cold readings against a control.
**Cut List.** Registration move of the `*` suites - buys P2 but breaks P3. Scheduler priority / weight-ordered buffering and a full
reorder by weights - rejected by ADR-242 Decision 29. A separate star queue launched from `_pj_drain` - adds a second launch site,
breaking "every launch decision flows through `_pj_fill`" (CTO, batch 2). The in-pass pre-scan variant - replaced by one post-loop
step (CTO, batch 2). A committed mutation suite and a committed model - the mutant outcomes are recorded in `summary.txt`, the model
was a plan-time direction check. Hand-tuned `--rows` ranges - cut for an exact contiguous search (CTO Q4).

**Order dependence of the `*` suites (issue criterion 2; CTO confirmed, batch 2).** Census of the six declared `*` suites and
derived `*`, read for any dependence on running before or after a specific suite: none has one.
`scripts/test-all-capacity-signal.test.sh` copies the real runner into stub sandboxes and runs `--capacity` (a content dependence on
the runner, not on registration order or other suites' state); `scripts/orphan-process-reaper.test.sh` greps `test-all.sh` for its
line-anchored `run_suite` registration line (AC33; registrations are untouched by shape B) and uses its own `/proc/$$/fd/N` fixtures;
the `-mutation` half symlinks the real `test-all.sh` read-only and runs the battery against mutated copies; `scripts/md-to-mrkdwn.test.mjs`
asserts `elapsedMs < 500` (wants an idle box, which the drain gives it); `scripts/cf-tunnel-liveness-gate-mutations.test.sh` works in a
sandboxed copy of `.github` and brackets its own mutations with `git status`; `run-registered-suites.sh` uses its own `mktemp`
log dir and resolves its `suite-durations.tsv` from its manifest directory. None reads `soleur-test-all-logs`, `TEST_TIMING_LOG` or
another suite's output. Two of them read the runner itself, so both are re-run in Phase 2. The pinned diff selects only
capacity-signal, so the readings exercise one of the six; the AC12 full-battery run (which exercises the parked order) is the gate
for the other five.

**Measured evidence (previous PR, `knowledge-base/project/specs/archive/20261106-151254-feat-one-shot-12013-replay-a-start-priority/measurements/`).**
Treatment: pool phase 1882 s, occupancy seconds {1 live: 112, 2: 462, 3: 72, 4: 1234}, 1332 idle slot-seconds, 1227 of them before
the barrier; post-barrier suites 50 / 962 slot-seconds (`operator-script` 188 s, `operator-ack-guard` 134 s,
`ship-phase-7-poll-fixtures` 143 s, `dev-ledger-parity` 82 s). Bound if the barrier is removed: the post-barrier work (962) fits the
idle slot-seconds before it (1227), so the pool phase approaches the end of `approval-guard1-mutation` (+1611 s pool-relative) plus a
short tail, a gain of about 150 to 270 s - a bound to be measured, not a result and not for the PR body. The pinned diff selects one
9 s `*` suite, so T1 measures barrier removal only; the effect when several `*` suites are selected is structural (each is solo
either way and the stranded drain disappears), not measured.

**Institutional learnings applied** (learnings-researcher, 2026-11-06): ADR-242 Decision 29 (registration order is start order;
defer launch, not registration, because verdicts print in registration order);
`2026-11-05-a-backfill-scheduler-and-its-sidecar-needed-mutation-batteries-not-a-green-suite.md` (trust `_pj_fill` clauses only after
mutating a copy of the runner through `TESTALL_TARGET_OVERRIDE`; an arm no mutant can redden is deleted); ADR-313 and the runbook
"Arm-split checklist"; `2026-11-01-rows-arm-lib-extraction-and-existence-deps.md` (never edit a battery file while one of its arms
runs); `SOLEUR_PJ_FIFO` must stay scrubbed at the arm boundary (`export -n`, `env -u`).

## Open Code-Review Overlap

One open code-review issue names a planned file: **#7942** (two mutation batteries named `*.mutation.sh` run in no gate) mentions
`scripts/test-all.sh`. **Acknowledge:** a different concern (registration of two orphaned batteries); it stays open.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-242** with an "Amendment - 2026-11-06 (#12231)" holding **Decision 30**: a `*` (drain barrier) suite is parked by the
pooled scheduler and launches solo at the drain, after every non-`*` job, in registration order; registration order, render order and
verdicts are unchanged; `SOLEUR_PJ_FIFO=1` stays strict FIFO. It also marks the Decision 29 sentence "Every `*` suite now waits for
the arms to drain" superseded. The decision text is written in the C-impl commit (it is true whatever the readings say); figures and
the protocol live only in `measurements/summary.txt` with a pointer. **Decision 31** (the `--rows` re-split) is added only if the
rebalance lands. No new ADR: this extends the decision that owns the scheduler.

### C4 views
No C4 change: the local test gate models no actor, vendor, container or data store, and no actor-to-surface access changes (checked
against all of `model.c4`, `views.c4`, `spec.c4`; `founder` and `contributor` exist, nothing is added). `plugins/soleur/test/c4-count-parity.test.sh`
ran green at plan time.

## Implementation Phases

Order matters: tests first (cq-write-failing-tests-before), runner second, rebalance as ONE separate droppable commit, readings
last on a quiet host (no editing or test runs during a reading; a reading is ~35 to 50 min). Commits: C-tests (RED; do not push it
alone, the branch is red until C-impl), C-impl (GREEN; T1 tree), C-rebalance (T2 tree = T1 + this; only if Phase 4.0 passes),
C-evidence (readings, ADR, runbook).

### Phase 0 - Baseline and tooling (no behaviour change)
0.1 Record the sorted `bash scripts/test-all.sh --enumerate-commands` rows (`SUITE_COMMAND` / `SUITE_COMMAND_DECLINED`) in the scratch
directory; lever 1 must leave them byte-identical, lever 2 may change only the three `--rows` argv cells (the diff result goes in
`summary.txt`; the TSVs are not committed).
0.2 Copy `derive.sh` and the method text from the archived measurements into this branch's `measurements/`; write `measure.sh` (clone,
symlink the two `node_modules`, set clone `origin/main` to the tree under test, apply the pinned-diff commit, run
`env -u CI SOLEUR_TEST_JOBS=4 TEST_TIMING_LOG=<f> bash scripts/test-all.sh --affected` with stamped output under `nice -n 10`). It records
loadavg and foreign `test-all.sh` pids at start and end, ABORTS the reading when the start load or the foreign-pid check is bad (threshold
stated in the script header), and prints one summary line per reading so a disturbed reading is cheap to redo. A derive cache is cold
only in a fresh clone; the protocol never reuses a clone. Pinned diff: the pick `7af192071d` (web-platform, 8 files): added files removed,
modified files restored to the parent's content, committed; expected `AFFECTED_SUMMARY selected=162 of=740`.

### Phase 1 - RED: the scheduler arms (scripts/test-all-parallel-scheduler.test.sh)
Edit the suite before the runner. Every `tl_check` carries a plain-language label naming the clause (a RED line reads "star-last: `*`
started before an independent ended", with the timeline dumped), so a contributor knows which property broke.
- **Retarget** the old bf3 arm (`holdQ, starS, indA2`) to the new contract: `indA2` starts while `holdQ` is live, `starS` starts after both
  end. **Retarget** the A4b `star` arm (`indA, starS, indB, indC`) to also assert `starS` starts after `indB`/`indC` end and verdict lines
  stay in registration order. (The existing `many` arm is the conflict-call cost ceiling; leave it alone and do not reuse its name.)
- **two stars** (`indA, starS, indB, starT, indC`, `starT` a derived `*`: no override, unreadable source - this arm expects a `[FAIL]`
  verdict and a non-zero exit for it since the source cannot run): the stars never overlap each other or anything, `starS` before `starT`.
- **drain-order** (`holdT, starS, headT`): `headT` (token-blocked behind `holdT`, registered after the star) runs before `starS`.
- **star-first** (`starS` registered first, then ten `ok` suites that stamp no timeline): the observation is runner-written and ordered,
  `[run] ok9 done` precedes `[run] starS started` in `ARM_OUT`.
- **torn reap** (`holdT, headT, starS`, the existing `torn` shape plus a parked `*`): `starS` runs, rc 0, no `[UNACCOUNTED]`.
- **signal while parked** (`sigred`-style with a `starS` registered): parked entries render `[UNACCOUNTED]`, accounting parity holds.
- **multi-token set** (only if `lane_declare` accepts `"* artifact:x"`; else record that it cannot be declared): parked like any `*`.
- **FIFO control**: `SOLEUR_PJ_FIFO=1` on the star fixture reproduces the frozen strict-FIFO launch order (new literal, recorded by
  running this arm against the UNMODIFIED runner in this phase - that run is the anchor); verdict lines and exit code equal backfill's.
- Must-PASS fixtures: a `*` suite registered last, and a run with zero `*` suites, both keep registration-order verdicts.
- Instrument self-test extended: the timeline checker FAILS on a sequential timeline and on a missing `star` label.
Run against the unmodified runner: the new arms must be RED for their own reason (the FIFO, must-PASS and instrument rows GREEN).

### Phase 2 - GREEN: park and release (scripts/test-all.sh)
Per CTO Q1/Q2 and batch-2 R1 (variant V2), backfill branch of `_pj_fill` only (the `_pj_fifo == 1` branch and `_pj_launchable` untouched):
- New global `_pj_draining=0`, set to 1 at the top of `_pj_drain` after the `_pj_mode` guard, never reset (`_pj_drain` is called once).
- In the pass, a candidate whose token set contains `*` (the word-bounded test `" $tok " == *" * "*`, the existing idiom) is **always
  parked**: `rest+=("$idx"); continue`. It is not added to `skip_tok` and does not set `any_q`.
- After the pass: if `_pj_draining == 1` and `_pj_live_n == 0` and `rest` is non-empty, launch `rest[0]` and drop it from `rest`. With an
  empty pool the first non-`*` candidate always launches (`lane_tokens_conflict` of a non-`*` set against an empty live set is false), so
  `rest` can then hold only parked `*` entries; launching the head of a pool-empty queue is legal in any case, so the step is also a
  deadlock-breaker. One `*` is released per fill; the next reap's fill releases the next.
- `_pj_launch`, `_pj_reap`, `_pj_submit`, solo / tmp attribution and `stamp_lock_holder` are untouched. Add no `_pj_sig` conjunct.
- Write the invariant once, in the `_pj_fill` comment block: "a parked `*` is invisible to backfill until the drain and is released
  only when the pool is empty after the pass"; the other stale sites point to it (see Files to Edit for the full list).
Run the Phase 1 suite: GREEN. Then `scripts/test-all-parallel-contention.test.sh` (C3 asserts only non-overlap), `-benchmark`,
`scripts/lib/test-suite-lanes.test.sh`, `scripts/test-all-capacity-signal.test.sh`, `scripts/orphan-process-reaper.test.sh` and
`-mutation.test.sh` (the two that read the runner), and every suite that copies or splices it
(`grep -l "TESTALL_TARGET_OVERRIDE\|test-all.sh" scripts/*.test.sh plugins/soleur/test/*.sh`).

### Phase 3 - Mutants and enumeration (evidence for Guard 1)
Run each Guard 1 mutant (one edit to a runner copy via `TESTALL_TARGET_OVERRIDE`) and put the outcome table in `summary.txt` (no
committed mutant harness). Re-take the enumeration: diff empty.

### Phase 4 - Rebalance (one droppable commit, gated)
4.0 **Paper check first.** Re-run the list-schedule what-if (4 slots, the 162 treatment walls in file order, the `*` suite removed,
lane tokens ignored; baseline must reproduce pool end 1611 s with `approval-guard1-mutation` starting at 945 s) over contiguous
splits using the per-arm walls (a, b, c scaled from the pooled walls by site share). Commit it as `measurements/rebalance_whatif.py`
with its output. Proceed only if the best contiguous split beats lever 1 alone by at least 30 s of predicted pool end; otherwise stop
here, record "not landed, paper-negative" for lever 2, and skip 4.1 to 4.4 and the T2 reading. Run 4.1 before the quiet-host window if
it proceeds.
4.1 Measurement-only hook (NOT committed): wrap the `in_range` call in a throwaway copy of the battery so each gated site appends
`_site_seq` and `$EPOCHREALTIME`; run the three arms concurrently in the measurement clone; derive per-site cost and the unconditional
share explicitly (the anti-vacuity floor says FLOOR minus `DECLARED_TOTAL`, about 100 passes - measure it). Commit
`measurements/site-costs.tsv` (header names the concurrency).
4.2 Choose the contiguous ranges that minimize the simulated pool end from 4.0 (not the maximum arm wall - that objective is wrong
after lever 1): a two-cut search over the 599 sites (about 180k pairs) in `measurements/split.py`, output committed. `DECLARED_TOTAL`
stays 599; arms stay three.
4.3 Apply in ONE commit: the three `run_suite ... --rows A-B` lines; `scripts/ci-oracle-lane-suites.txt` (three rows);
`scripts/ci-oracle-lane.test.sh` argv-drift mutant (its `sed 's|--rows 1-193|...|'` literal is the old first range - derive the
substitution from the manifest's first range so it still edits the argv); hand-edit the three arm rows in `scripts/suite-durations.tsv`
(`src=estimate`, never `measured`); re-derive the `plugins/soleur/test/ci-pr-affected-replay-a` row of
`scripts/suite-weight-exemptions.tsv` (`cap_ms` at most 1.3 x the new weight, or delete it when the new weight fits the default cap;
keep the #11679 reason). `regenerate-shard-manifest.py --incremental --write` is only run as a check that it reports no diff (labels and
leg pins are unchanged). Do not edit the battery while any arm runs.
4.4 Run `scripts-shard-totality.test.sh`, `scripts/ci-oracle-lane.test.sh`, `scripts/lib/test-suite-lanes.test.sh`,
`scripts/test-all-weight-drift.test.sh`, `scripts/test-all-corpus-weight-budget.test.sh`, the affected-index ratchet / `ci-pr-affected-audit`
(labels unchanged, so no new accept rows are expected), and one standalone run of each new arm.

### Phase 5 - Cold readings (quiet host, back to back)
Order **C, T1**, then **T2 only if Phase 4.0 passed**, then **C2** if the smaller of the C-T1 and C-T2 pool-phase deltas is under
150 s, a reading looks disturbed, or T1 is more than 30 s worse than C (CTO R3); compare against the faster control. C = the
merge-base tree (`git merge-base HEAD origin/main`; currently `78fbd47b9a`, tree-identical to `07def23087`), `SOLEUR_PJ_FIFO` unset (not
the FIFO knob). T1 = the C-impl tree. T2 = T1 + C-rebalance. Fresh clone per reading (own git-common-dir, own advisory lock, empty derive
cache), the two `node_modules` symlinked. Wait with the Monitor tool and an until-loop on the summary line, never a polling
`run_in_background`. Record per reading: wall, cold derive, pool start (`[parallel] mode engaged`), pool phase, each arm's start and
wall, idle slot-seconds, seconds with at most one suite live (reported, not gated), the `*` suite's start/end and what was live at its
start (must be nothing), loadavg start/end, foreign pids, failures.

### Phase 6 - Evidence, docs, hand-off
`measurements/summary.txt` (method, table, mutant outcomes, caveats, "not claimed": the pinned diff selects one 9 s `*` suite so T1
measures barrier removal only); ADR-242 Decision 30 (and 31 if landed); runbook line 18 of
`knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` (the launch-order sentence "a queued `*` still blocks
everything after it") rewritten to the parked-`*` contract - line 15 ("ordered after a drain" describes print order) stays true and is
not edited. PR body: `Ref #12013` always; `Closes #12231` only per AC7 else `Ref #12231`; the rebalance paragraph says "landed",
"neutral on pool phase, kept for arm balance" or "not landed"; the expected CI effect in one line. #12263 stays the follow-up
(`Ref #12013`); if lever 2 is paper-negative, add a line there that the rebalance pays once `approval-guard1-mutation` starts first.

## Files to Edit

- `scripts/test-all.sh` - `_pj_draining`, always-park and the post-loop release in the backfill branch of `_pj_fill`, flag set in
  `_pj_drain`; stale prose rewritten (the `SOLEUR_PJ_FIFO` header paragraph, the scheduler design comment, the `_pj_fill` block,
  and the START-FIRST comment above the replay arms that says a queued `*` "blocks every later launch"); in the rebalance commit the
  three `ci-pr-affected-replay-{a,b,c}` `run_suite` argv lines.
- `scripts/lib/test-suite-lanes.sh` - the `THE MODEL.` header paragraph only (its drain-barrier sentence gains "it launches at the
  drain, after every non-`*` suite").
- `scripts/lib/test-suite-lanes.test.sh` - the section-7 header comment (it states a queued `*` blocks later launches); assertions
  unchanged.
- `scripts/test-all-parallel-scheduler.test.sh` - retargeted bf3 and A4b arms, new arms, instrument self-test, FIFO literal, header
  list and the comments that state the old barrier contract.
- Rebalance commit only: `scripts/ci-oracle-lane-suites.txt`, `scripts/ci-oracle-lane.test.sh`, `scripts/suite-durations.tsv`
  (three arm rows), `scripts/suite-weight-exemptions.tsv` (the replay-a row). Not edited: the shard-legs and heavy TSVs (no `--rows`
  in them; labels and pins unchanged).
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` - amendment.
- `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` - line 18 only.
- Verified, expected unchanged: `scripts/test-all-parallel-contention.test.sh` (C3), `-benchmark`,
  `plugins/soleur/test/ci-pr-affected-replay.test.sh` (`DECLARED_TOTAL=599`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12231-star-suites-last/{tasks.md,decision-challenges.md}` and `measurements/`:
  `measure.sh`, `derive.sh`, `summary.txt`, `rebalance_whatif.py` (+ output), the per-reading `*.suites.tsv`, `*.timing.tsv`,
  `*.notes.txt`, and, only if Phase 4.0 passes, `site-costs.tsv` and `split.py` (+ output). (Stamped 18k-line logs, enumeration TSVs,
  the plan-time model and mutant scripts are not committed.)

## Guard Contract

### Guard 1 - Park-and-release contract of the backfill scheduler

**Property.** In a pooled backfill run a `*`-token suite runs alone, launches only after every non-`*` job has been launched and
reaped (the drain), in registration order among `*` suites, delays no non-`*` suite, and leaves verdict order, labels and
`SOLEUR_PJ_FIFO=1` strict-FIFO order exactly as they were.

**Assembly.** Every launch decision flows through `_pj_fill`; its callers are `_pj_submit` (after each registration and in the
saturation loop), `_pj_reap` (after each reap) and `_pj_drain` (the reap/fill alternation and the torn-reap path). The `*` token reaches
it from an explicit `lane_declare ... "*"` override, from the classifier's fail-closed derivation for an unreadable or unmappable
source, and from the `|| printf '*'` fallback in `_pj_submit` (unreachable without shadowing `lane_tokens_for`; not fixtured). The guard
quantifies over the resolved token set, not a label list: the arms cover an override `*` and a derived `*`. `_pj_fill` has two branches
(FIFO and backfill): FIFO is pinned unchanged by the frozen order, backfill by the arms.

**Mutation matrix** (one edit to a runner copy via `TESTALL_TARGET_OVERRIDE`, each must turn the named arm RED; derived from the design):

| # | Edit to the runner copy | Must redden |
|---|---|---|
| M1 | delete the park, or park but still add the `*` to `skip_tok` / set `any_q` | star-last (retargeted A4b) and bf3 arms |
| M2 | post-loop release without `_pj_draining` (release whenever the pool is empty) | star-first arm |
| M3 | post-loop release without the `_pj_live_n == 0` check, or launching ALL of `rest` (second member: a second `*` beside the first) | two-stars arm and the A4/C3 non-overlap checks |
| M4 | REORDER: run the post-loop release step before the pass | drain-order arm (`starS` before `headT`) - deleting the step would redden any suite, moving it reddens only one that observes the order |
| M5 | park inside the `_pj_fifo == 1` branch / `_pj_launchable` | FIFO frozen-order literal |
| M6 | set `_pj_draining=1` at the top of `_pj_submit` instead of `_pj_drain` | star-first arm |
| M7 | test `$tok == "*"` instead of the word-bounded match (only if the multi-token arm is declarable) | multi-token arm |

**Harness rows.** H1 (edit to the SUITE): flip an expected order in the star-last `tl_check`; the arm must go RED. H2 (must-PASS,
non-canonical): a `*` registered last and a run with zero `*` suites stay green with registration-order verdicts. H3 (the arm's own
dispatch): the timeline checker fails on a timeline missing the `star` label ("0 checked" is not green).

**Anchor.** The FIFO literal is a stored value compared to the runner, so one diff could weaken both. The independent anchor is the
Phase 1 run of the FIFO arm against the UNMODIFIED merge-base runner, whose order must equal the literal; the PR records that run.

### Guard 2 - Arm tiling and argv agreement after a re-split (existing guards; only if the rebalance proceeds)

**Property.** The three registered `--rows` ranges tile 1..`DECLARED_TOTAL` exactly once and every consumer of the argv and of the
arm price agrees.

**Assembly.** Chokepoints: the totality extractor in `plugins/soleur/test/scripts-shard-totality.test.sh`, `scripts/ci-oracle-lane.test.sh`
G4 (manifest argv vs registration argv), `rows_gate_floor` in the battery, and `scripts/test-all-corpus-weight-budget.test.sh` (price vs
exemption cap). Consumers that restate the ranges or the price and are not chokepoints: `scripts/ci-oracle-lane-suites.txt`, the argv-drift
mutant's `sed` literal, `scripts/suite-durations.tsv`, `scripts/suite-weight-exemptions.tsv`.

**Mutation matrix** (scratch tree, run once, outcome recorded in `summary.txt`):

| # | Edit | Must redden |
|---|---|---|
| G1 | gap: first arm ends one site early | scripts-shard-totality |
| G2 | overlap: second arm starts one site early | scripts-shard-totality |
| G3 | update `test-all.sh` only, leave `ci-oracle-lane-suites.txt` | ci-oracle-lane G4 `MEMBER-ARGV-DRIFT` |
| G4 | re-seed the replay-a price, leave the old exemption cap | test-all-corpus-weight-budget (slack bound) |
| G5 | leave the old `1-193` literal in the drift mutant's `sed` | the mutant stops editing the argv and its `check_contains` goes RED |

**Harness rows.** H4 (must-PASS, non-canonical): the DP's own output is a valid tiling that is not the old split, and it passes the
same suites. **Anchor.** `DECLARED_TOTAL=599` lives in the battery, outside this diff's edit set; the merge-base value is recorded in the PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement #12231 - run the drain-barrier `*` lane suites last (or defer them to the drain in `_pj_fill`/`_pj_drain`)" [brief] | Phase 2; `scripts/test-all.sh` | mapped |
| 2 | "honoring its re-evaluation criteria (check `scripts/test-all-capacity-signal.test.sh`, `scripts/orphan-process-reaper*.test.sh`, `scripts/md-to-mrkdwn` for order dependence" [brief] | Research Insights (order dependence); decision-challenges.md | mapped |
| 3 | "scheduler rows: a `*` suite never overlaps another, verdict and rendered order unchanged, `SOLEUR_PJ_FIFO=1` stays the strict-FIFO control" [brief] | Phase 1 arms; Guard 1 | mapped |
| 4 | "then rebalance the replay arms' `--rows` split by weight (the arms pool at 1513 / 570 / 530 s)" [brief] | Phase 4 (paper check first, CTO R2); Guard 2 | mapped |
| 5 | "Measure in a private clone with its own git-common-dir and link node_modules first; take cold readings of a pinned diff (one control, treatments)" [brief] | Phases 0.2 and 5 | mapped |
| 6 | "Do NOT raise `budget_seconds`" [brief] | AC9 | mapped |
| 7 | "PR body uses `Ref #12013` (not Closes) unless a measured run meets the bar; `Closes #12231` is fine for the `*`-last change if its criteria are met" [brief] | Phase 6; AC7, AC10 | mapped |
| 8 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/test-all.sh` park/release | "defer them to the drain in `_pj_fill`/`_pj_drain`" (ask 1) | asked |
| `scripts/test-all-parallel-scheduler.test.sh` arms | ask 3 | asked |
| Stale-prose rewrites (`test-all.sh` comments, `test-suite-lanes.sh` / `.test.sh` comments, runbook line 18) | - | inferred - justification: each states "a queued `*` blocks everything after it", which the change makes false; stale prose is how the barrier is re-introduced |
| ADR-242 Decision 30 | - | inferred - justification: plan skill Phase 2.10 makes the ADR a deliverable of the plan that changes the scheduler contract |
| rebalance edits (registrations, oracle files, durations, exemption row) | ask 4 | asked |
| `suite-weight-exemptions.tsv` row, `ci-oracle-lane.test.sh` mutant literal | - | inferred - justification: the exemption cap is a slack bound on the replay-a price and the mutant hard-codes `1-193`; left alone both go red (found by reading the files) |
| `measurements/` and `measure.sh` | ask 5 | asked |
| Follow-up issue #12263 | - | inferred - justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for levers left out |
| Guard Contract and mutant run | - | inferred - justification: the deliverable includes a guard (the scheduler contract); plan skill Phase 2.12 |

### Split Assessment

- Subsystems touched: 3 - `scripts/`, `knowledge-base/engineering/`, `knowledge-base/project/specs/`
- Planned files: about 12 edited + about 10 measurement files | Estimated changed lines: about 350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, with the rebalance as one droppable commit

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Phase 1 arms RED on the unmodified runner, each for its own named reason; FIFO, must-PASS and instrument rows GREEN there.
- [ ] AC2: `bash scripts/test-all-parallel-scheduler.test.sh` GREEN after Phase 2; `test-all-parallel-contention`, `-benchmark`, `lib/test-suite-lanes.test.sh`, `test-all-capacity-signal`, `orphan-process-reaper` and `-mutation` GREEN.
- [ ] AC3: Guard 1 mutants M1 to M6 (M7 if declarable) all die; H1 reddens, H2 stays green; the outcome table is in `summary.txt`.
- [ ] AC4: the sorted enumeration diff is empty after C-impl; after C-rebalance only the three `--rows` argv cells differ.
- [ ] AC5: backfill and FIFO print identical verdict lines in identical order with the same exit code on the star fixtures; the FIFO literal matches the unmodified-runner run (Phase 1).
- [ ] AC6: the T1 pool log shows every `*` suite launching with nothing else live, after the last non-`*` suite ended (a structural property, pinned deterministically by the Phase 1 fixtures). "Seconds with at most one suite live" against C is REPORTED, not gated: it depends on the host's other load (`cq-ac-must-not-depend-on-concurrent-sessions`).
- [ ] AC7 (claim criterion for the PR wording, not a property of the diff; the deterministic proof is AC1 to AC6): the park is kept on the structural evidence; T1 pool phase at least 100 s below the faster control, scheduler rows green and failures limited to the known clone artifact `apps/web-platform [repo-wide+component]` decide `Closes #12231` versus `Ref #12231` and the wording. A T1 more than 30 s worse than the faster control forces C2; the park is reverted only if C2 reproduces the regression or the log shows an overlap or a `*` launching before the last non-`*` ended. The claim says T1 measures barrier removal only (one 9 s `*` suite selected).
- [ ] AC8 (rebalance, only if Phase 4.0 passed; CTO Q3b + R2): in T2 pool phase at most T1's plus 30 s; the largest-to-smallest ratio of the arms' pooled walls at most 1.5; totality, the anti-vacuity floor, `ci-oracle-lane` G4 and `test-all-corpus-weight-budget` pass; failure set unchanged; predicted arm walls within about 15 percent of T2's measured pooled walls (a miss means the rebalance is dropped or recorded as informational only). A gain is CLAIMED only if T1 minus T2 is at least 50 s; otherwise the PR says "neutral on pool phase, kept for arm balance" or drops the commit. If Phase 4.0 failed: "not landed, paper-negative", no rebalance commit.
- [ ] AC9: `git diff --quiet origin/main...HEAD -- .soleur-test-gate.json plugins/soleur/scripts/affected-tests.sh` exits 0 (`budget_seconds` untouched).
- [ ] AC10: PR body uses `Ref #12013` always, `Closes #12231` only per AC7, and ends with the attribution line.
- [ ] AC11: ADR-242 Decision 30 and runbook line 18 updated; `git grep -nF -e 'queued \`*\`' -e 'blocks everything after it' -e 'blocks every later' -- scripts knowledge-base/engineering/operations` returns nothing, and the only hits in the ADR-242 file are Decision 29 sentences the amendment marks superseded; `c4-count-parity` green.
- [ ] AC12: `python3 scripts/lint-guard-contract.py` on this plan, `bash scripts/test-all.sh` (full battery - the runner changed, so the gate runs full and this exercises the parked order) with all six `*` verdicts green, other results green or only pre-existing failures per `wg-when-tests-fail-and-are-confirmed-pre`.

### Post-merge (operator)

None. The readings are taken before merge; nothing is deployed.

## Test Scenarios

The Phase 1 arm list is the scenario list (star-last, two stars, drain-order, star-first, torn reap, signal while parked, multi-token,
FIFO control, must-PASS shapes) plus the Guard 2 matrix when the rebalance proceeds.

## User-Brand Impact

**If this lands broken, the user experiences:** a developer-machine test gate that wrongly reports green or red for a suite, or runs a
wall-clock or whole-box `*` suite beside live workers (a spurious `elapsedMs < 500` or `/proc` failure). No end-user surface; the cost
is lost contributor time and trust in the local gate.
**If this leaks, the user's data / workflow / money is exposed via:** no vector - the change reads and writes no user data,
credentials or network; the runner only schedules local processes.
**Brand-survival threshold:** none. threshold: none, reason: local developer-gate scheduling and test-range bookkeeping only; no auth,
schema, API, credential or user-data path is touched.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two CTO rounds on 2026-11-06 (decision-challenges.md): scheduler parking over a registration move, release at drain
entry, the C/T1/T2 protocol with the keep rule, the measured contiguous split; and, after the plan-review panel, the post-loop release
variant, the paper-check gate on lever 2, the AC7 amendment, and the six-suite order-dependence confirmation. No Product/UX surface
(no UI file in either Files list); no legal, finance, marketing, sales, support or operations implication.

## Observability

Gate not triggered: the Files lists are repo-root `scripts/`, knowledge-base documents and measurement data, outside the gate's code
paths, and the change adds no service, route, cron or infrastructure surface. The signal is the scheduler's own per-suite
`[run] <label> started/done` lines.

## Non-Goals / Deferrals

- Start-first for the remaining long suites (`approval-guard1-mutation` 666 s, `argv-bearer-sweep` 343 s, `destroy-ask-mutation` 242 s)
  and eager reaping of finished workers: **#12263** (new, `Ref #12013`).
- Narrowing the replay arms' selection edge: #12151. Narrowing the `lock:test-all` derivation: #12152. Both pre-existing and still deferred.
- Raising `budget_seconds`: forbidden by the brief.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or carries filler text fails `deepen-plan` Phase 4.6; this one is filled.
- `scripts/test-all.sh` is the runner: a runner edit makes the PR's own gate run the FULL battery, and that run is not a measurement.
- The timeline arms rely on release files (`mk_rel_fixture`); a fixture whose releasing suite never starts only ends by its timeout, so a
  RED arm can look like a hang - read the dump, not the wall time.
- Never edit `plugins/soleur/test/ci-pr-affected-replay.test.sh` while a reading (or an arm) is running; bash re-reads by byte offset.
- The plan-time model over-predicts on the treatment reading (2497 vs 1882 s); no model number is a result.
- Three foreign `test-all.sh` runs share the CPU today; `measure.sh` aborts a reading started beside them.
- The C-tests commit leaves the branch red; do not push it alone (squash merge makes this safe).
