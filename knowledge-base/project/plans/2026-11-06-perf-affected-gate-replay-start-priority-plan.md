---
title: "perf(tests): start the replay arms first in the local affected gate"
date: 2026-11-06
slug: perf-affected-gate-replay-start-priority
branch: feat-one-shot-12013-replay-a-start-priority
issue: 12013
lane: single-domain
type: perf
---

## Overview

The local affected gate (`scripts/test-all.sh --affected`, run by `soleur:ship`, `soleur:work` and `soleur:review`)
is still about 3100 s cold against the 600 s bar of #12013. After the pool (width 4), conservative backfill and the
lock-token override of the previous PR (#12149, ADR-242 amendment of 2026-11-05) the remaining critical path is
`plugins/soleur/test/ci-pr-affected-replay-a`: it starts 1.2 to 1.6 ks into the run and alone runs 1.5 ks, so the run
ends when it ends.

The cause is structural and was not visible before this plan: registration order is start order. `_pj_submit` queues a
suite as the registration stream reaches it and blocks only when the pool is saturated; `_pj_fill` can only choose among
suites already queued; and a queued `*` (drain barrier) suite blocks every later registration. The three replay arms are
registered at position 113 to 115 of 160 selected suites, inside the glob loop of the second `if want_scripts` block
(the `"$f" == "plugins/soleur/test/ci-pr-affected-replay.test.sh"` arm of `scripts/test-all.sh`), behind the one selected `*` suite `scripts/test-all-capacity-signal`. A scheduler
"priority" therefore cannot start them earlier without buffering the registration stream.

This plan moves the three registrations to the first position of the first `if want_scripts` block (a static start-first
registration; labels, argv and gating unchanged), guards the order with a test over the real `--enumerate-commands`
output, and measures the effect in a private clone. It is `Ref #12013`: the model predicts a cold gate of about 2.5 ks,
not 600 s, and the PR does not claim the bar.

Deferred by the brief and not done here: #12151 (replay-arm selection edge), #12152 (lock-token derivation), reaping
finished workers earlier (evidence bar on #12013). Deferred by the CTO ruling of 2026-11-06 and filed: #12231 (run the
`*` suites last). `budget_seconds` is not raised.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #12013 is OPEN and its comment trail matches the brief (the 2026-11-05 amendment names longest-first ordering or a
start priority for replay-a as the next lever; the follow-up comment of 2026-11-06 repeats it). PR #12149 is merged
(`4e0f90b56c`, on this branch's base). #12128 is MERGED and #12110 CLOSED, so #12151 is unblocked but the brief defers it.
`gh pr list --search 12013` shows only this branch's own draft PR #12228. The collision pre-check also listed three
`test-all.sh` processes owned by `feat-one-shot-bun-pair-ratchet-accept-cleanup`: a sibling session is running the battery,
which is load on the shared machine and a reason to record loadavg at each measured reading, not a duplicate of this work.
Cited symbols exist on `HEAD`: `_pj_fill()`, `_pj_submit()`, `_pj_drain()` in `scripts/test-all.sh`, the three replay
`run_suite` lines in the glob loop, the three replay `lane_declare` calls in `scripts/lib/test-suite-lanes.sh`, and the
`## Amendment — 2026-11-05 (#12013)` heading of ADR-242. ADR corpus check (Phase 0.6 item 4): ADR-242 considered and rejected unconditional skip-ahead, a default-off
knob, a suite-result memo and narrowing the token derivation; it records the ordering lever as the next one and rejects
none of this plan's mechanism. ADR-262 (CI-only batteries) and ADR-276 (local-first ship) do not touch ordering. ADR-240 considered: the shard manifest is label-keyed and order-independent; its positional fallback is documented as non-portable, which is the degraded mode named in Risks below.

### Property List and Cut List (Phase 0.6b)

Properties the ask needs (the ask names the mechanism "longest-first ordering or a start priority"):

- P1. The longest suite of the local affected gate (`replay-a`, about 1.5 ks pooled) starts at pool start, not behind the
  registration stream.
- P2. The suite set, labels, argv, gating, verdict order, exit contract and CI shard assignment are unchanged; each arm is
  registered exactly once.
- P3. The change is measured, in a private clone, against a same-base control, and the claim is limited to what the readings
  show.
- P4. The order cannot silently drift back (a later edit that re-inserts the arms in the glob loop, duplicates one, or
  changes a `--rows` range).

Mechanisms considered and their disposition (mechanism -> property -> what already covers it):

| Mechanism | Property | Disposition |
|---|---|---|
| Static start-first registration (move 3 lines) | P1 | KEEP. Smallest change; registration order is start order. |
| Scheduler-level declared priority or weight-ordered buffering | P1 | CUT (CTO R1). Needs registration buffering (changes streaming and lock-holder stamping); weights are the wrong input (replay-a 1033 s committed vs 1549 s pooled); full reorder by committed weights models worse than baseline. |
| Longest-first full reorder by measured wall | P1 | CUT. An oracle: needs walls known before the run; modelled at 2129 and 2020 s, only 70 to 250 s better than hoisting a, b, c. |
| Move the `*` suites last | a second property (no mid-stream barrier strands slots) | CUT from this PR (CTO R2), filed as #12231. |
| A new "start-first" lane table or declaration file | P4 | CUT. Three labels; the guard over `--enumerate-commands` is the whole declaration. |
| A new guard suite file | P4 | CUT. Extend `scripts/lib/test-suite-lanes.test.sh`, which already reads the enumeration in registration order and owns the replay-arm checks. |

The ask's assertion "the remaining critical path is replay-a" was checked against the authority (the archived timing rows
and a schedule model, below), not taken from the brief: it holds for the pool phase, but the model shows a second,
independent cost (the mid-stream barrier) that the brief did not name.

### Value-proposition measurement (Phase 0.6c)

The claimed saving is measured at plan time, by a model validated against the measured readings. Commands that produced the
numbers (all in `knowledge-base/project/specs/feat-one-shot-12013-replay-a-start-priority/measurements/model/`; run from the
repo root as `python3 whatif2.py . <archived-measurements-dir>`; the archived dir is
`knowledge-base/project/specs/archive/20261106-052833-feat-one-shot-12013-affected-gate-lock-chain/measurements`):

- `bash scripts/test-all.sh --enumerate-commands` for the registration order (`enum.txt`), and `lane_tokens_for` over each
  row for the token sets (`tok.sh`, `tokens.tsv`).
- `sim.py` replays the `_pj_fill` backfill (width 4, strict registration-order streaming, `*` barrier, tokens) over the
  measured pool-concurrent walls of readings r1, r2 and r3.

Validation against the measured readings: pool phase 2713 s modelled vs 2728 s measured (r1) and 2920 vs 2942 (r3);
`replay-a` start 1165 s vs 1166 s measured (r1) and 964 vs 967 (r3). The model is within 1 percent on the quantity this
plan moves, which is what permits using it to rank levers (the previous PR validated its model the same way).

Pool-phase seconds, r1 / r3 / r2 (r2 was the FIFO control, modelled with backfill for comparison only):

| Variant | r1 | r3 | r2 |
|---|---|---|---|
| baseline (registration order) | 2713 | 2920 | 2585 |
| hoist replay-a only | 2264 | 2753 | 2402 |
| **hoist replay-a, -b, -c (this plan)** | **2197** | **2267** | **1984** |
| hoist top 7 suites by measured wall | 2143 | 2546 | 2220 |
| full reorder by committed weights | 2513 | 2756 | 2451 |
| full reorder by measured wall (oracle) | 2129 | 2020 | 1764 |
| `*` suite last only (#12231) | 2120 | 2461 | 2111 |
| hoist a, b, c plus `*` last (#12231) | 1897 | 1962 | 1705 |
| packing floor (sum of walls / 4) | 1824 | 1875 | 1609 |

Expected effect of this plan: -516 s (r1), -653 s (r3), -601 s (r2) of pool phase; with a cold derive of 230 to 335 s the
cold gate is about 2.5 ks, still about 4 times the 600 s bar. Two further observations the model gives:

- Hoisting only `replay-a` leaves 70 to 490 s on the table versus hoisting all three arms (r3: 2753 vs 2267), because
  `-b` and `-c` (about 700 s each) then start behind the barrier. The three arms move together.
- With the replay arms hoisted, the pool is idle for 1493 slot-seconds (r1), much of it behind the one `*` suite
  `test-all-capacity-signal`, which waits for `approval-guard1-mutation` (729 s) to drain. That is the #12231 lever.
- Robustness with other `*` suites selected (orphan-process-reaper, its mutations, md-to-mrkdwn injected at their
  registration positions, walls assumed 60 / 120 / 30 s, `model/star-injection.py`): hoisting stays a net gain, -282 to
  -631 s. Hoisting does not make a mid-stream barrier worse than it was.

Model limits, stated: walls are the measured pool-concurrent walls of one diff (web-platform, 160 of 733 suites) and are
treated as fixed, but a suite started at pool start sees different load than one started late; the committed tokens are those
of `HEAD` (the readings used the commit before the previous PR's final edits; the validation shows this did not matter for the
selected set); machine load differs between readings (loadavg 9 to 38). The CTO's evidence bar (R3) is therefore a measured
reduction, not the model.

### Institutional learnings applied

- `2026-11-05-a-backfill-scheduler-and-its-sidecar-needed-mutation-batteries-not-a-green-suite.md`: a green suite shows only
  that fixtures match the author's code; mutate each clause on a copy; aim fault injection at the process that runs the suite;
  scrub the A/B knob at the arm boundary (this plan adds no knob and keeps `SOLEUR_PJ_FIFO` demoted as it is).
- `2026-11-03-a-slow-gate-issue-measured-an-opt-in-feature-nobody-had-enabled.md`: editing `scripts/test-all.sh` degrades the
  affected gate to the full battery (`reason=runner-changed`), so this PR's own local gate cannot be the measurement.
- `2026-10-11-a-runner-arm-above-the-splice-window-fires-inside-every-sibling-sandbox.md`: anything above the splice window
  of `test-all.sh` is copied into every sandboxed runner. The moved lines sit after `tc_acquire "test-all"` (the scheduler
  suite's splice start anchor, the `start_anchor = 'tc_acquire "test-all"'` assignment in `scripts/test-all-parallel-scheduler.test.sh`), so they fall inside the
  replaced window; the work phase greps `build_sandbox` and `cp .*test-all.sh` in `scripts/*.test.sh` before editing.
- `2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`: an ordering guard needs a
  mutant that MOVES the line and expects red (Guard 1 row 1).
- `2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md` and
  `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`: after moving registrations, confirm every suite
  is still reached (the orphan linter and the shard-totality suite are the checks; they stay in the verification list).
- `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`: never edit `scripts/test-all.sh` while a run uses it
  (a false `unexpected EOF`); the measured readings run from a clone, not from this worktree.
- `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`: run the readings detached with an explicit rc
  file, never piped through `tail`.

### Open Code-Review Overlap

One open code-review issue names a planned file: #7942 ("Two mutation batteries in plugins/soleur/test/ are named
*.mutation.sh and run in no gate") mentions `scripts/test-all.sh`. **Acknowledge:** a different concern (two suites that are
registered nowhere); this plan neither registers nor moves them, and the issue stays open.

### Research Reconciliation - Spec vs. Codebase

| Claim (brief / amendment) | Reality | Plan response |
|---|---|---|
| "Next lever: longest-first ordering or a start priority for it" | A scheduler priority cannot act on a suite not yet registered; registration order is start order and a queued `*` blocks later registrations. | Static start-first registration (CTO R1); the scheduler is not touched. |
| "the `replay-a` suite starts 1.2 to 1.6 ks into the run" | True, and it is behind the single selected `*` suite (`test-all-capacity-signal`) plus a serial `lock:test-all` chain of 57 suites summing about 1.0 to 1.2 ks. The model reproduces the start within 3 s. | Hoist ahead of both. The barrier itself is #12231. |
| "longest-first ordering" generally | Full reorder by the committed weights models worse than the baseline (committed replay-a is 1033 s vs 1549 s pooled; weights are CI-shard measurements). | Cut; named set only. |
| "reaping finished workers earlier" is a lever | Deferred in the brief; not touched. | Out of scope; evidence bar stays on #12013. |

## Problem Statement

`bash scripts/test-all.sh --affected` selected 160 of 733 suites on the pinned diff. The suite phase (2728 to 2942 s) is
bounded below by the packing floor (sum of walls / 4 = 1824 to 1875 s) and above, in practice, by when `replay-a` can start
plus its 1549 to 1956 s wall. `replay-a` is late only because of where the registration stream reaches it. Hoisting it (and
its two siblings) removes about 500 to 650 s of modelled pool-phase wall at no scheduling risk, since the three arms carry an
empty token set and drive their own `mktemp -d` sandbox.

## Proposed Solution

### Phase 0 - Pre-edit baseline and splice audit (no behaviour change)

- 0.1 Save the full pre-change `bash scripts/test-all.sh --enumerate-commands all` output to `measurements/before.enum.tsv`, and record the replay-arm rows and the first five registrations from it (`grep -n '^SUITE_COMMAND'`), and `--print-selection`'s `selected=` for the
  pinned diff's paths, into the measurement notes. These are the frozen "before" values of Guard 1.
- 0.1b Run `bash scripts/test-all.sh --enumerate-commands --affected scripts` once before and after on the pinned diff and record whether the arms appear as `SUITE_COMMAND` rows (declined rows are emitted separately, so the `all` stream is the guard's source and the affected stream is checked once, not assumed).
- 0.2 `grep -n 'build_sandbox\|cp .*test-all.sh' scripts/*.test.sh tests/scripts/*.sh plugins/soleur/test/*.sh` and read each sandbox builder's splice
  anchors; confirm the moved lines stay inside the `tc_acquire "test-all"` .. `tc_epilogue` window.
- 0.3 Read all three C4 model files in full (`model.c4`, `views.c4`, `spec.c4`) and run
  `bash plugins/soleur/test/c4-count-parity.test.sh`, to back the "no C4 impact" line below with a green run rather than a grep.

### Phase 1 - Failing guard first (cq-write-failing-tests-before)

Add section 7 to `scripts/lib/test-suite-lanes.test.sh` (see Guard 1 for the matrix; the mutant dir is created under the file's existing `_h_dir`, not under a new `trap`). It must be RED on the unmodified
runner (the arms are at positions 113 to 115 of the 160 selected suites, i.e. 407 to 409 of the `all` enumeration the guard reads) before Phase 2 and GREEN after.

### Phase 2 - Move the registrations

In `scripts/test-all.sh`:

1. In the first column-0 `if want_scripts; then` block (directly under the `# Pre-suite bash/python tests — scripts shard.` comment), before `run_suite "tests/hooks/incidents"`, insert the
   three `run_suite` lines unchanged (`"plugins/soleur/test/ci-pr-affected-replay-a" bash
   plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 1-193`, `-b` `--rows 194-386`, `-c` `--rows 387-599`), with the
   comment block that now explains (a) why they are first (registration order is start order; the arms are the longest suites,
   about 1.5 ks / 0.7 ks / 0.65 ks pooled, with an empty token set; a queued `*` suite blocks every later registration), (b)
   the ROWS-SPLIT facts that were at the old site (the boundary lives in the flag argument, never the label; the union tiling
   1..DECLARED_TOTAL is asserted by `plugins/soleur/test/scripts-shard-totality.test.sh`; a DECLARED_TOTAL bump must land with
   a re-split), and (c) that `scripts/lib/test-suite-lanes.test.sh` section 7 pins the position.
2. In the glob loop, keep `if [[ "$f" == "plugins/soleur/test/ci-pr-affected-replay.test.sh" ]]; then ... continue; fi` with
   the three `run_suite` lines removed and only `continue` left (with a comment pointing at the start-first block). The
   `"$f" == "..."` text is what `scripts/lint-orphan-test-suites.sh` and `plugins/soleur/test/scripts-shard-totality.test.sh`
   read to subtract the glob member; removing the `if` would register the suite file as a plain suite as well.
3. Literal path in each arm's argv, never `"$f"` (the totality checker resolves the battery from the `run_suite` command token).

No change to `_pj_fill`, `_pj_submit`, `_shard_selects`, `run_suite`, the lane table values, `scripts/suite-shard-legs.tsv`,
`scripts/suite-durations*.tsv`, or `budget_seconds`.

### Phase 3 - Verify structural gates (local, fast)

`bash scripts/lib/test-suite-lanes.test.sh`, `bash scripts/lint-orphan-test-suites.sh`,
`bash plugins/soleur/test/scripts-shard-totality.test.sh`, `bash scripts/test-all-parallel-scheduler.test.sh`,
`bash scripts/ci-oracle-lane.test.sh` (the `MEMBER-ARGV-DRIFT` check compares argv with the registration), `bash scripts/guard-vacuity-floor.test.sh` (the new floor is written as a statement, like section 6's `arm_gate`, not as a counter `if`), and
`bash scripts/test-all.sh --enumerate-commands` for the first rows. Each is run once as a control before the edit.

### Phase 4 - Measurement in a private clone (CTO R3, amended Q3 to Q5)

Never in a ship path, in a private clone with its own git-common-dir (`git clone <worktree> /data/git-repositories/jikig-ai/measure-clone-<name>`;
the clone is the only way the pool engages, because it has its own advisory lock; the previous clone `measure-clone-r1` is an operator-only leftover and is not touched).
Method as in the archived `summary.txt` of the previous PR, with these specifics (the method is a measurement method only; it bypasses nothing in a ship path):

- Pinned diff: the previous PR's pick `7af192071d` (web-platform, 8 files; added files removed and modified files restored to
  the parent's content, committed), so the selection is 160 of about 733 as in the three prior readings. Not this PR's own diff.
- Control: a checkout at the same base without the Phase 2 edit, `SOLEUR_PJ_FIFO` unset. Treatments: the Phase 2 tree.
- Order in one session, back to back on the same host: control, treatment 1 (treatment 2 under the conditions below). `origin/main` in the clone is set
  to the tree under test so the runner edit does not degrade the gate to full.
- Command: `env -u CI SOLEUR_TEST_JOBS=4 TEST_TIMING_LOG=<file> bash scripts/test-all.sh --affected`, output stamped per line,
  run detached with an rc file. Record loadavg and heavy concurrent processes at each start and end.
- Before the first treatment reading: confirm in the clone that `--enumerate-commands` lists the three arms as the first three
  rows (R3), and that the treatment clone really holds the edit.
- Per reading derive: wall, cold derive, suite phase, `replay-a` start and wall, share of the pool phase with at most one
  suite live, pass and fail counts, failed suite names; compare the measured `replay-a` start with the model's prediction (the
  model is re-run on the control reading's walls).
- Readings (CTO Q4, 2026-11-06, adaptive): one control and one treatment; report the `replay-a` start offset (read from the
  `[run] ... started` lines) as the primary evidence. Run a second treatment if the first treatment's pool-phase gain is within
  150 s of the 300 s bar on either side, if any criterion fails, or if a reading is disturbed or the two loadavg records differ
  materially. The PR states how many readings were completed.
- Landed means all of: `replay-a` starts within 120 s of pool start in every treatment; pool-phase wall at least 300 s below
  the control in every treatment; no failure that the control does not share (the known clone artifact
  `apps/web-platform [repo-wide+component]` and anything classified in the previous amendment are expected). Recorded, not
  gated (CTO Q3): the model's `replay-a` start versus measured for the control reading (5 percent) and the measured treatment start.
- If a treatment misses the bar (CTO Q5): keep the move, record the measurement as informational, say "not landed" in the PR body
  and the ADR and claim no saving; revert only if a treatment shows a failure the control does not share.
- Raw rows are committed under `knowledge-base/project/specs/feat-one-shot-12013-replay-a-start-priority/measurements/`
  (timing TSV, start/end notes, `summary.txt`); the 18k-line stamped logs are not committed.

### Phase 5 - Record: ADR-242 amendment, tracker comment

- ADR-242: new `## Amendment — 2026-11-06 (#12013)` via `soleur:architecture`: the finding (registration order is start
  order; the arms sat behind a `*` barrier and a 57-suite `lock:test-all` chain), the decision (static start-first
  registration), the measured table (three readings, model validation, loadavg), what it does not claim (600 s), alternatives
  considered (scheduler priority/buffering, weight-ordered reorder, hoist replay-a only, `*`-last in the same PR), the
  deferral pointer to #12231, and the unchanged limits (reap timing, #12151, #12152).
- Comment on #12013 after merge (agent-run): the measured result, the remaining gap, the pointers to #12231, #12151, #12152
  and the reap evidence bar. #12013 stays open.

## Files to Edit

- `scripts/test-all.sh` - add the start-first block (first `if want_scripts`), reduce the glob-loop special case to `continue`.
- `scripts/lib/test-suite-lanes.test.sh` - new section 7 (start-first order guard, with fixtures and mutation rows).
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` - amendment.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12013-replay-a-start-priority/measurements/` - readings (timing TSVs, start notes,
  `summary.txt`); the planning-phase `model/` directory and `model-output.txt` already exist there.
- `knowledge-base/project/specs/feat-one-shot-12013-replay-a-start-priority/tasks.md` (plan phase).

Not edited, and verified by `git diff --stat origin/main...HEAD` in the PR: `scripts/lib/test-affected-paths.sh`,
`scripts/lib/test-suite-lanes.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations*.tsv`,
`scripts/suite-shard-legs.tsv`, `plugins/soleur/scripts/affected-tests.sh` (the budget), `.soleur-test-gate.json`.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-06 (full text in `knowledge-base/project/specs/feat-one-shot-12013-replay-a-start-priority/decision-challenges.md`): R1 static
start-first registration over a scheduler priority; R2 the `*`-last lever is a follow-up (#12231); R3 cold readings of
one pinned diff in a private clone, same-base control, landed = start within 120 s, at least 300 s lower, no new failures
(amended the same day: adaptive one control plus one treatment, model agreement recorded not gated, keep the move on a miss);
R4 the guard reads the real enumeration and asserts exactly-once, bare-path-zero and arms-before-the-first-`*`-and-`lock:test-all`-row (amended: no argv literals, no position pin), nothing about other suites.

No Product/UX surface: no new page, component, flow or copy. Product, Marketing, Legal, Finance, Operations, Sales and
Support: no implications (developer tooling).

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user artifact. An operator or agent sees a local gate that runs the
  replay arms later than intended (no worse than today) or, if the move were wrong, a registration missing or doubled. The
  guard and the orphan and totality gates red on either; CI's required `test` check remains the only merge gate.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing; no data, credential or network surface is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern` - a wrong local ordering is caught by the required CI check and nothing here reaches a customer surface. threshold: none, reason: the touched paths (`scripts/`, `knowledge-base/`) are developer tooling and ship no customer-visible behaviour.

## Observability

```yaml
liveness_signal:
  what: the runner's live `[run] <label> started (pid=N)` lines, whose order shows which suites started first, and the `[parallel] mode engaged - width=N` banner
  cadence: per gate run (each ship, work, review and pre-push invocation)
  alert_target: the invoking operator or agent terminal; the gate marker `AFFECTED_GATE ...` is parsed by ship Phase 4
  configured_in: scripts/test-all.sh (_pj_launch)
error_reporting:
  destination: stderr of the runner and the exit code; no Sentry surface (developer tooling on the operator's machine)
  fail_loud: the order guard exits 1 with a named FAIL row if an arm is registered after the first `*` or `lock:test-all` row, or is not registered exactly once
failure_modes:
  - mode: an arm drifts back into the glob loop, is registered twice, or its --rows range changes
    detection: scripts/lib/test-suite-lanes.test.sh section 7 over the real --enumerate-commands output, plus lint-orphan-test-suites and scripts-shard-totality
    alert_route: the suite is auto-registered by the scripts/lib glob in the local gate and the CI test shard; a red blocks the PR
  - mode: the arms start late again because a new `*` suite is registered before them
    detection: the same guard (arms before the first `*` row)
    alert_route: same as above
  - mode: the gain does not materialise on a different diff mix
    detection: per-suite start and wall rows in TEST_TIMING_LOG and the live [run] started lines (replay-a start offset from the first started line)
    alert_route: the ADR-242 ledger and the next reading on #12013
logs:
  where: the runner's durable per-suite logs under ${SOLEUR_SCRATCH_BASE:-/var/tmp}/soleur-test-all-logs and TEST_TIMING_LOG
  retention: 14 days (SOLEUR_TEST_ALL_LOG_GC_DAYS default, existing)
discoverability_test:
  command: bash scripts/lib/test-suite-lanes.test.sh
  expected_output: "[pass] replay arms start first"
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (new `## Amendment — 2026-11-06 (#12013)`), via the `soleur:architecture` skill, as Phase 5 describes: decision
(static start-first registration of the replay arms), evidence (the validated schedule model and the three readings), the
`Alternatives considered` additions (scheduler priority or buffering; weight-ordered full reorder; hoisting replay-a alone;
folding the `*`-last move into this PR), and the deferral to #12231. No new ADR ordinal, so no ordinal-collision exposure.

### C4 views

No C4 impact. The work phase reads all three model files in full (Phase 0.3) and runs `bash plugins/soleur/test/c4-count-parity.test.sh`
before this line is final. Checked at plan time against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
(1083 + 148 + 54 lines): (a) external human actors - the operator-side actor is unchanged; (b) external systems - GitHub Actions
CI is unchanged and no vendor is added; (c) containers / data stores - the local test runner and the affected gate are not
modelled (a case-insensitive search for test-all, affected, local gate, replay and scheduler finds only unrelated prose about
hosts, Redis, Inngest and Cloudflare); (d) actor-to-surface access relationships - none change. No cron monitor, heartbeat or
workflow is added, so the derived cardinalities in the edge prose do not move.

### Sequencing

The ADR amendment is written in this PR after the measurement, describing the as-measured state. Nothing is postponed to a
separate issue except the explicitly ruled-out #12231 lever, which has its own tracker.

## Guard Contract

### Guard 1 - Start-first order of the replay arms (`scripts/lib/test-suite-lanes.test.sh` section 7)

**Property.** In the runner's real registration stream (`bash scripts/test-all.sh --enumerate-commands all`), each of
`plugins/soleur/test/ci-pr-affected-replay-a`, `-b` and `-c` appears exactly once, the bare suite path
`plugins/soleur/test/ci-pr-affected-replay.test.sh` appears zero times, and each arm's row index is lower than the index of the
first row whose lane tokens contain `*` and of the first row whose lane tokens contain `lock:test-all` (the two things the arms
used to sit behind). Nothing is asserted about the relative order of any other suite, the total count, or the `--rows` ranges:
`plugins/soleur/test/scripts-shard-totality.test.sh` already proves the three ranges tile 1..DECLARED_TOTAL and
`scripts/ci-oracle-lane.test.sh` (`MEMBER-ARGV-DRIFT`) compares each arm's argv with the registration (CTO Q1, 2026-11-06; if
either check is found not to cover argv at work time, put the argv literals back into this guard).

**Assembly.** The registration stream is the SAME channel the scheduler's input flows through: every registration passes the
`run_suite` chokepoint and is emitted as a `SUITE_COMMAND` row. The sites that can register an arm: the start-first block, the
glob loop (the literal arms if they are moved back, and `run_suite "$f" bash "$f"` for the bare suite file if the special-case
`if` is removed), and a second `if want_scripts` block. One enumeration is checked (`all`; the affected-mode stream is the same
code path, filtered at the chokepoint). The guard quantifies over EVERY `SUITE_COMMAND` row (counts of exact label matches and
a first-index scan), not over the rows it expects. The pure function `start_first_ok <rows>` takes the rows as input so the
live check and the synthetic cases run the SAME code.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Runner-copy mutant: move the three `run_suite` lines back into the glob loop (the pre-change layout). The copy lives under the section's existing temp dir (`_h_dir`, covered by the file's `EXIT` trap), written to `$sb/scripts/test-all.sh` with `$sb/scripts/lib` symlinked to the repo's `scripts/lib` and the shard-manifest tsv files copied beside it (the runner resolves them through `dirname "${BASH_SOURCE[0]}"`, precedent: `build_sandbox` in `scripts/test-all-parallel-scheduler.test.sh`), never placed inside the tracked tree, and enumerated with `(cd "$REPO_ROOT" && bash "$sb/scripts/test-all.sh" --enumerate-commands all)`; the edit is a regex over the runner text keyed on the label pattern, not a literal naming the suite path. Cost: one extra enumeration of about 1 s | RED (arms behind the first `*` and `lock:test-all` rows) |
| 2 | Synthetic rows: arms last | RED |
| 3 | Synthetic rows: `-a` and `-b` first, `-c` after a `lock:test-all` row (second member after a compliant first) | RED |
| 4 | Synthetic rows: `-a` registered twice | RED (exactly once) |
| 5 | Synthetic rows: the bare suite path registered as a plain suite as well | RED (zero occurrences) |
| 6 | Synthetic rows: empty input, or labels matching nothing (the guard's own dispatch) | RED (`n_arms == 3`, written as a statement like section 6's `arm_gate`, so `scripts/guard-vacuity-floor.test.sh` does not read it as a counter floor) |
| 7 | Live check on the real enumeration | GREEN after Phase 2, RED before (the RED-before proof of cq-write-failing-tests-before) |

**Harness rows.** (H1) The same function decides the live enumeration and the synthetic rows 2 to 6, so a function that rejects
everything fails the must-PASS row. (H2) Must-PASS inputs that are NOT the canonical order: the arms in order `c a b`; the arms
first followed by an arbitrary non-arm list of a different length including a non-arm label that merely contains `replay`;
a `*` row and a `lock:test-all` row placed after the arms.

**Anchor.** No stored value is compared; the guard reads the live stream and the lane table (`lane_tokens_for`).

## Scope Check

### Ask Mapping

| Ask (brief) | Plan item |
|---|---|
| Resume #12013; gate about 3100 s cold vs 600 s | Overview, Problem Statement |
| Next lever: longest-first ordering or a start priority for replay-a | Phase 2 (static start-first registration; CTO R1) |
| Deferred: #12151, #12152, reaping finished workers earlier | Not touched; named in Overview |
| Measure in a private clone with its own git-common-dir, never in a ship path | Phase 4 |
| Do not raise `budget_seconds` | Files-not-edited list; AC |
| `Ref #12013` not `Closes` unless a measured run meets the bar | Overview, AC, Phase 5 |
| Technical rulings via CTO, persisted in decision-challenges.md | Domain Review; decision-challenges.md |

### Plan-Item Provenance

| Item | Provenance |
|---|---|
| Static start-first registration | asked (the brief's "start priority"), form ruled by the CTO |
| Order guard in the lanes suite | inferred, justified: cq-write-failing-tests-before and the CTO's R4; a moved registration with no guard silently drifts back |
| ADR-242 amendment | inferred, justified: ADR-242 is the ledger for this lever (the 2026-11-05 amendment says "recorded on #12013"). The runbook sentence and a `test-suite-lanes.sh` comment edit were cut at plan review (no requirement; the code comment is the single place that states why) |
| `*`-last lever | not in this PR; filed as #12231 (CTO R2) |

### Split Assessment

One PR. The edit is three lines moved plus a guard; the measurement is a record, not a second change. The `*`-last lever is split
out on purpose (a confounded measurement). No further split.

## Acceptance Criteria

Gates (deterministic, no dependence on machine load): AC1 to AC7, AC9. Recorded observations (loaded machine): AC8.

### Pre-merge (PR)

- [ ] AC1. `scripts/lib/test-suite-lanes.test.sh` section 7 is RED on the unmodified runner (control run first) and GREEN after
  Phase 2; the runner-copy mutant (row 1) and each synthetic RED row (2 to 6) turn it RED and the H2 must-PASS rows stay green;
  the header comment of the file lists sections 6 and 7.
- [ ] AC2. `bash scripts/test-all.sh --enumerate-commands all` lists `ci-pr-affected-replay-a`, `-b`, `-c` as the first three
  `SUITE_COMMAND` rows and each exactly once; argv byte-identical to before (`diff` of the three rows vs the Phase 0.1 record).
- [ ] AC3. `bash scripts/lint-orphan-test-suites.sh`, `bash plugins/soleur/test/scripts-shard-totality.test.sh`,
  `bash scripts/test-all-parallel-scheduler.test.sh`, `bash scripts/ci-oracle-lane.test.sh` and `bash scripts/guard-vacuity-floor.test.sh` are green, and `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 (an `oracle-inputs-changed` warning is expected because `scripts/test-all.sh` is edited). Section 7 introduces no new line that names the replay suite path: it reuses section 6's `replay_file` variable and the `*ci-pr-affected-replay-*` label pattern (the accept TSV accepts only the existing boundary line, and AC5 forbids editing it).
- [ ] AC4. The suite population is unchanged: the registration count of `--enumerate-commands all` before and after (`diff <(sort measurements/before.enum.tsv) <(bash scripts/test-all.sh --enumerate-commands all | sort)` shows only the position change, no label or argv change; sorted, so it is empty) is equal and the
  set of labels is identical (`diff <(sort before) <(sort after)` empty).
- [ ] AC5. `git diff --stat origin/main...HEAD` shows no change to `scripts/lib/test-affected-paths.sh`,
  `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations*.tsv`, `scripts/suite-shard-legs.tsv`,
  `plugins/soleur/scripts/affected-tests.sh` or `.soleur-test-gate.json`; no `budget_seconds` change anywhere.
- [ ] AC6. ADR-242 amendment (2026-11-06) written (decision, the three headline numbers, the "does not claim 600 s" statement, the
  alternatives, pointers to `measurements/summary.txt`, #12231, #12151, #12152); the explanatory comment block sits above the moved
  registrations in `scripts/test-all.sh` (the runbook is not edited: the comment is the single place that states why).
- [ ] AC7. The PR's required CI `test` check is green on the PR head (the PR edits the runner, so CI runs the full battery);
  the PR body says that this run is not the measurement; `bash plugins/soleur/test/c4-count-parity.test.sh` is green; the PR
  body says `Ref #12013`, no `Closes`.
- [ ] AC8. (Recorded observation, CTO R3 as amended by Q3 to Q5.) One control and one treatment (a second treatment under the Phase 4
  conditions) of the pinned diff in a private clone with its own git-common-dir, each with loadavg and heavy processes at start
  and end, committed under `measurements/`. Landed = `replay-a` starts within 120 s of pool start; pool-phase wall at least 300 s
  below the control; no failure the control does not share. The model-versus-measured start for the control (5 percent) is a
  recorded note. The PR states the number of completed readings and says "not landed" if a criterion is missed.
- [ ] AC9. #12231 exists (filed during planning) with re-evaluation criteria and the milestone; the deferral section of the PR
  body names #12231, #12151, #12152 and the reap evidence bar.

### Post-merge

- [ ] AC10. #12013 receives a comment (agent-run) with the measured result and the remaining gap; it stays open.

## Test Scenarios

1. Unmodified runner: section 7 is RED (arms at 407 to 409 of the `all` enumeration; 113 to 115 of the selected 160). After Phase 2: GREEN.
2. `--affected` on a diff that selects none of the arms: no behaviour change (the arms are declined at the chokepoint as before);
   the `skip_suite` pairing is untouched.
3. `TEST_GROUP=scripts-heavy` or `bun`: the arms are not registered (the start-first block is inside `want_scripts`).
4. CI shard legs (`SCRIPTS_SHARD=k/N`): the arms are still assigned by the manifest (`scripts/suite-shard-legs.tsv` legs 2, 7, 4);
   `scripts-shard-totality` proves every registration lands on exactly one leg.
5. Serial mode (`SOLEUR_TEST_JOBS=1` or `CI`): the arms now run first instead of at position 113; verdicts print in registration
   order, so the report's first blocks are the arms. Exit contract unchanged.
6. A pool run on the pinned diff: the first four `[run] ... started` lines are the three arms and one other suite; `replay-a`
   starts within seconds of pool engagement.
7. A second `*` suite selected (for example orphan-process-reaper): the barrier now drains the arms but the arms are no longer
   behind it; the modelled net effect is still a gain (-282 to -631 s).

## Dependencies & Risks

- Risk: the first registrations now load the machine at pool start (three heavy arms plus one suite). Mitigation: the width is
  unchanged (4); the arms already ran concurrently with each other and with other suites in the measured readings. The
  measurement records loadavg.
- Risk: in serial mode and CI shards the roughly 25-minute arms now run before the cheap suites, so a cheap red surfaces later in a
  serial run. Accepted: CI shards run in parallel legs, and the pool gate prints a provisional red at reap.
- Risk: serial-mode and CI-shard report order changes (arms first). Mitigation: CI sets `CI` and runs serial per shard with the
  shard manifest, order-independent; the verdict lines are keyed by label; `TEST_TIMING_LOG` rows are label-keyed.
- Risk: the positional shard fallback (used only if a manifest is absent or mismatched) assigns by registration ordinal, so
  moving the arms shifts the ordinal of every registration between the new and the old position by 3 for that degraded mode only. Both
  surfaces state this mode is not portable between machines and totality holds under any order; the manifest covers all three
  arms.
- Risk: the model overstates the gain on diffs with a different suite mix. Mitigation: the PR claims only the three measured
  readings, and says so.
- Risk: a sibling session loads the machine during a reading (the collision pre-check saw one). Mitigation: record loadavg at
  start and end; a reading that is disturbed is recorded as such and repeated, not averaged away.
- Dependency: none blocking. #12128 merged and #12110 closed, so #12151 could start separately; not part of this PR.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none`
  with a reason.
- The guard asserts nothing about any other suite's order. A future PR that wants another suite to start first edits the guard's
  declared list and the block together (one place each); it does not register ahead of the arms silently.
- Do not move `test-all-capacity-signal` or any `*` suite in this PR (CTO R2): it would confound the measurement of this lever.
- Never edit `scripts/test-all.sh` while a measurement run uses it; readings run from the clone, and the clone is not updated
  mid-reading.
- Hoisting only `replay-a` is a trap: the model shows `-b` and `-c` then start behind the barrier and the gain shrinks by
  70 to 490 s. The guard requires all three.
- The measurement control is a same-base checkout with `SOLEUR_PJ_FIFO` unset, not `SOLEUR_PJ_FIFO=1`; the knob changes the
  scheduler, which this PR does not touch.
