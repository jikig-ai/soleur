---
title: "chore(tests): measure per-site cost of the replay arms and decide what the local affected gate still needs (Ref #12013)"
date: 2026-11-07
slug: measure-replay-site-costs-for-local-gate
branch: feat-one-shot-12013-site-cost-measurement
issue: 12013
type: chore
lane: cross-domain
---

Spec lacks a valid `lane:` (no spec.md exists for this branch) - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-07 (agents: performance-oracle on the measurement method, test-design-reviewer on the ACs, CTO for rulings R1 to R4; the full-roster fan-out was reduced to the two lenses that bear on a measurement-only plan, and the gates 4.6 to 4.13 were run by hand: user-brand, PAT, scope-check, rule-id, issue-number and SHA checks all pass).

### Key Improvements
1. Floor arithmetic corrected from the committed rows (1495 s t1, 1391 s control2, not 1546 s); control2's end state corrected.
2. Validation hardened: split-half block stability, b/c-fit contention scale with a's alone-stretch at ratio 1.0, raw (unclamped) costs, per-row pristine charge, model reproduction within 15 s in start order.
3. Gate matched to the measured noise: 60 s nominal gain, 81-combination paired robustness including approval-guard1-mutation's own wall.
4. ACs made runnable; raw guard/rc/wall files committed so the table is rebuildable; AC2 allow-list matches the ship-time archive move.

### New Considerations Discovered
- control2's run ended on the post-star drain (`dev-ledger-parity`, 1890 s), not on approval-guard1-mutation.
- `/var/tmp/m12231` raw logs are still present but volatile.
- The ratchets that sweep `measurements/*.sh` read tracked files only (`git add -N` first).

## Overview

The local affected-test gate is still about 2.1 ks cold against the 600 s bar of #12013. Two ordering levers
have landed (replay arms first, `*` suites last). This change finds, from measured data, where the remaining
wall goes: it times every gated site of the three replay arms, re-runs the rebalance paper check on those
costs, and records what #12231 and #12263 each need to close.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #12013, #12231 and #12263 are all OPEN with no closing PR; the `*`-last change is
squash `5a98235b4d` and is an ancestor of this branch; the only open PR naming #12013 is this branch's own draft #12310 (collision
pre-check exit 10, no foreign run). Held: the 40 s pool-phase delta, the 13-mutant table and the unmeasured per-site costs (all in the
archived `summary.txt` and `decision-challenges.md`). Stale or corrected:

- The brief and the earlier CTO ruling say `DECLARED_TOTAL` stays 599. On this tree it is 602 and the registered arms are `--rows 1-193 /
  194-386 / 387-602` (`scripts/test-all.sh`, `scripts/ci-oracle-lane-suites.txt`). `rebalance_whatif.py` hard-codes 599 and a baseline
  assertion (1611 / 945) that only holds on the old reading's file, so it must be adapted, not re-run as is. The runbook
  `ci-test-scripts-sharding.md` still says `of 578` (history prose, left alone).
- The brief names replay-a (about 1.5 ks) as the long pole. In the committed readings it is not what ends the run: in t1 the pool end
  (1845 s pool-relative) is `approval-guard1-mutation`, which started at pool offset 765 s and ran 1080 s, while replay-a ended at 1487 s
  (358 s earlier); in control2 `approval-guard1-mutation` started at 778 s, ran 880 s and ended 294 s after replay-a, but the old star barrier then adds a drain and control2 ends at 1890 s on `dev-ledger-parity`. So
  the recoverable ordering gain is the late start of `approval-guard1-mutation` (#12263's lever), and the replay-arm split matters only
  to the extent replay-a sits above the packing floor (sum of walls / 4, 1495 s for t1 and 1391 s for control2: it does not).
- Floor arithmetic (measured by the deepen pass from the committed `suites.tsv`, 162 suites each): sum of walls / 4 is 1495 s (t1, 5979 s) and 1391 s (control2, 5563 s); with cold derive of 216 s and 234 s that is about 1.71 and 1.63 ks against 600 s. The 1546 s figure in the brief and the rulings is the previous PR's treatment file and is not used here. No ordering or splitting lever in
  this plan can reach the bar; `Closes #12013` is therefore not reachable from this PR.

**Property List (Phase 0.6b).**

1. #12231 has a recorded disposition that does not rest on the 40 s delta alone.
2. A measured per-site cost table exists for the 602 gated sites of the replay test plus each arm's unconditional share.
3. The rebalance decision is made on that table under a stated gate, in both orderings, with the result recorded whether or not a split lands.
4. #12263's levers are priced on paper from measured costs and the critical path is named from committed rows.
5. No reading used as evidence is disturbed, and `budget_seconds` is untouched.

**Cut List.** Committed instrumentation in `scripts/lib/rows-range.sh` (an opt-in cost log) -> property 2 -> cut: the CTO ruling keeps the
hook uncommitted (a `.patch` in `measurements/` is its reproducibility record), and the `in_range` seam already carries `_site_seq`. A new
site-cost subcommand in `scripts/ci-pr-affected-replay.py` -> property 2 -> cut: a 40-line stamp patch plus a Python table builder in
`measurements/` covers it. A new reading harness -> property 5 -> cut: `measure.sh` / `derive.sh` from the archived spec already exist
(only needed if a rebalance reaches a cold reading). Raising `budget_seconds` -> none -> cut (2400 s, `.soleur-test-gate.json`).

**ADR corpus (Phase 0.6 item 4).** ADR-242 Decision 29 rejected "a scheduler-level priority or weight-ordered buffering" and a "full
reorder by measured wall"; the CTO ruling (F4) keeps any start-first follow-up as a hand-listed registration hoist for that reason. This
plan edits no scheduler and no registration order, so it adds no ADR decision (see Architecture Decision section).

**Rulings.** Recorded in `knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/decision-challenges.md` (rows F1 to F5, G1
to G3, R1 to R4). Summary: #12231 closes on a recorded decision, `Ref` in the PR; site cost by concurrent standalone hooked arms with median over 2
to 3 runs; the 1.5x bound is replaced by a robustness gate (60 s nominal, 81 combinations); step 3 is paper-only here; zero cold readings unless a split clears the gate.

**Learnings applied** (`knowledge-base/project/learnings/`):
`2026-11-05-a-new-tool-was-built-for-a-case-the-existing-one-already-handled-and-the-measurement-method-changed-the-mechanism.md`
(read the runner's own banners in the first 60 s and abort a reading that did not engage the pool; compose totals from raw rows and check
interval overlap; do not rm -rf a clone inside a hooked session), `2026-11-05-a-backfill-scheduler-and-its-sidecar-needed-mutation-batteries-not-a-green-suite.md`
(run the repo ratchets over new files before the first commit: `fixture-relative-assert`, `guard-vacuity-floor`, `grep-q-pipe-guard`;
scrub `SOLEUR_PJ_FIFO` at arm boundaries), `2026-11-03-a-slow-gate-issue-measured-an-opt-in-feature-nobody-had-enabled.md` (check the
dispatch site before attributing a slow run to a missing mechanism).

**Sweep scope.** Non-archived `.sh` files under `knowledge-base/project/specs/<feat>/` are scanned by `plugins/soleur/test/fixture-relative-assert.test.sh`
and `.claude/hooks/grep-q-pipe-guard.test.sh` (the previous PR's `measure.sh` tripped both). Any script committed into `measurements/`
must pass both before the first commit; data files and `.patch` / `.py` files are not swept by those two.

## Research Reconciliation — Spec vs. Codebase

| Brief or ruling claim | Reality on this tree | Plan response |
|---|---|---|
| `DECLARED_TOTAL` stays 599 (Q4, 2026-11-06) | 602 since `8da7b8359f` (#12258); arms `--rows 1-193 / 194-386 / 387-602` | All tables, asserts and ranges use 602; the 3 added sites sit in arm c's range, so the t1 pooled walls are compared on a 602-range rebuild (Phase 4.2) |
| The long pole is replay-a (about 1.5 ks) | In t1 and control2 the run ends on `approval-guard1-mutation` (late start); replay-a ends 294 to 360 s earlier | Step 2 still measures replay-arm sites (asked), but the paper check also prices the start-first ordering and #12263 gets the evidence (Phase 4.4) |
| `rebalance_whatif.py` is reusable | Hard-codes 599, per-arm uniform cost, and a baseline assertion valid only for the previous PR's file | New `site_cost_whatif.py` adapted from it: reads the measured table, reconstructs launch order from `run.log`, asserts it reproduces t1 within 5% before any verdict |
| Cold readings are a work task (brief step 4) | CTO F5/G1: zero readings on the no-rebalance path; C then T2 only if a split passes the gate | Phase 5 is conditional, with the full recipe and the rejection rule written out |
| Raw logs are "not kept" | `/var/tmp/m12231/{control2,t1}/{run.log,timing.tsv}` still exist (volatile) | Phase 1 copies them first; reap latency for #12263's eager-reap lever is derived from them |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-read the archived summary.txt and decision-challenges.md. Decide what #12231 needs to close" [brief] | Phase 0 (rulings F1), Phase 6.3 | mapped |
| 2 | "Do not close it on the 40 s result alone." [brief] | F1 ruling: closure rests on the recorded structural decision; Phase 6.3 comment | mapped |
| 3 | "Measure per-site cost before changing any split: run the three replay arms concurrently with an uncommitted timestamp hook around `in_range`, and commit the site-cost table" [brief] | Phases 2 and 3, `site_costs.tsv` | mapped |
| 4 | "Re-run the paper check on measured costs, not weights. Only land a rebalance if the paper gain is at least 30 s." [brief] | Phase 4.3 gate (30 s is the floor to consider a split, 60 s nominal to land: ruling R4), conditional Phase 5 | mapped |
| 5 | "#12263 is the follow-up for starting the remaining long suites first. Its comment says per-site costs must be measured before more rebalance work, so do that after step 2." [brief] | Phase 4.4 (paper-only, F4), Phase 6.2 | mapped |
| 6 | "Take cold readings the same way: private clone with its own git-common-dir, node_modules linked, a pinned diff, one clean control plus treatments, and reject any reading disturbed by sibling load" [brief] | Phase 5 (conditional, G1), rejection rule in Phase 3.1 | mapped |
| 7 | "Do NOT raise budget_seconds." [brief] | AC2 (diff on `.soleur-test-gate.json` empty) | mapped |
| 8 | "PR body uses `Ref #12013`; `Closes #12013` only if a measured run meets the 600 s bar." [brief] | Phase 6.5, AC8 | mapped |
| 9 | "the plan should specify those runs as work-phase tasks with exact commands, the load1/foreign-test-all rejection rule, and where the site-cost table is committed" [brief] | Phases 3 and 5, `measurements/site_costs.tsv` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 copy of volatile `/var/tmp/m12231` inputs | asks 3 and 5 ("Re-run the paper check on measured costs") | asked |
| `site_cost_table.py --selftest` | — | inferred — justification: a table builder with an unchecked subtraction would certify a wrong table; the selftest recovers known synthetic costs and fails on the no-subtraction mutant |
| ADR-242 amendment (Phase 6.4) | ask 1 ("Decide what #12231 needs to close") | asked |
| Reap-latency rows | ask 5 ("per-site costs must be measured before more rebalance work") | asked |
| Robustness gate (81 combinations) | ask 4 ("Only land a rebalance if the paper gain is at least 30 s") | asked, tightened by ruling F3 |
| Comment on #12013 with the floor arithmetic | ask 8 | asked, required by ruling F5 |

### Split Assessment

- Subsystems touched: 2 - `knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/`, `knowledge-base/engineering/architecture/decisions/` (conditional path adds `scripts/` and `plugins/soleur/test/` registration lines)
- Planned files: about 14 (zero-rebalance path) | Estimated changed lines: about 700 (mostly data)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The start-first lever (#12263) is a separate PR by ruling F4.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; an operator reads a wrong site-cost table and mis-sizes a later gate change (wasted agent time on ship).
- **If this leaks, the user's data is exposed via:** no vector; the committed rows are suite names, ordinals and seconds from a synthetic fixture battery.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is measurement data and one ADR amendment on the zero-rebalance path, and a re-split of test-registration ranges on the conditional path; neither touches a customer surface.

`threshold: none, reason: the touched paths are knowledge-base artifacts and CI test-registration ranges for a fixture battery; no auth, schema, API or customer data path.`

## Open Code-Review Overlap

#7942 ("Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate") names `scripts/test-all.sh`. Acknowledge: a different concern (battery naming), and the zero-rebalance path does not edit `scripts/test-all.sh`; on the conditional path only three registration argv lines change.

## Implementation Phases

Paths below are relative to the worktree root unless absolute. `M=knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/measurements`.
Rejection rule for EVERY reading (site-cost run or cold): abort before start when `cut -d' ' -f1 /proc/loadavg` is above 9.0 or any other `test-all.sh` run is live (the `foreign_runs` function of the archived `measure.sh`); record both facts again at the end; a reading whose end state is bad is DISTURBED, is not a result, and is replaced. Do not raise `budget_seconds` (`.soleur-test-gate.json`, 2400).

### Phase 0 - Rulings (done at plan time)

CTO rulings F1 to F5 and G1 to G3 are in `decision-challenges.md`. Nothing is left to ask.

### Phase 1 - Preserve volatile inputs (before anything long runs)

1.1 Copy `/var/tmp/m12231/control2/{run.log,timing.tsv}` and `/var/tmp/m12231/t1/{run.log,timing.tsv}` into the session scratchpad directory (not the repo; the logs are about 1.8 MB each). Commit `$M/launch_order.t1.tsv` and `$M/launch_order.control2.tsv` (suite, start offset, wall, extracted from the `[run] ... started` and `done` stamps) so the what-if reads committed rows, not the volatile logs. If a file is gone, the committed `control2.suites.tsv` / `t1.suites.tsv` of the archived spec are the fallback and `summary.txt` says so.
1.2 Identify which 3 sites `8da7b8359f` added: `git diff 78fbd47b9a..HEAD -- plugins/soleur/test/ci-pr-affected-replay.test.sh | grep -E '^\+(mutate|ow_mutate) '` and map each to its ordinal (count `^mutate |^ow_mutate ` lines in file order up to it). Record the ordinals; Phase 4.2 uses them to rebuild the t1 prediction.

### Phase 2 - Hook, runner, table builder (no measurement yet)

2.1 In a throwaway clone (not the worktree), edit `scripts/lib/rows-range.sh` and save `git diff` to `$M/rows-range-site-cost-hook.patch`. Content: a `_sc_stamp()` helper that appends `"<seq>\t$EPOCHREALTIME"` to `$SITE_COST_LOG` (uses `${EPOCHREALTIME:?bash 5 required}`; the absolute-path check lives in `site_cost_run.sh`); stamp `0` at the end of `rows_parse_args`, stamp `$_site_seq` right after the increment in `in_range`, stamp `EOF` at the entry of `rows_gate_floor`. Do not add a line-start `DECLARED_TOTAL=` or a literal `--rows <digits>-<digits>` to the file (census constraints in its header). The patch is applied only inside measurement clones.
2.2 Write `$M/site_cost_run.sh <rep>` (rep in r1..r3). Steps, in order: refuse a relative or empty output dir; load and foreign-run guard (rejection rule above); `git clone -q --no-checkout /data/git-repositories/jikig-ai/soleur "$O/clone"`; `git checkout -q --detach "$TREE"` where `TREE` is the exact commit under test (`git rev-parse HEAD` of the worktree, clean tree, recorded); `git apply "$M/rows-range-site-cost-hook.patch"`; read the three arm ranges from `scripts/ci-oracle-lane-suites.txt` (rows whose label ends `-a`, `-b`, `-c`; never hard-code); `mkdir -p "$O/tmp-a" "$O/tmp-b" "$O/tmp-c"` (the arm does `mktemp -d "$TMPDIR/..."` and exits 2 on a missing dir); launch the three arms concurrently, each as `LC_ALL=C TMPDIR="$O/tmp-<arm>" SITE_COST_LOG="$O/<arm>.stamps.tsv" nice -n 10 env -u CI bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows <A-B>` with stdout to `$O/<arm>.out`, rc to `$O/<arm>.rc` and start/end `EPOCHREALTIME` to `$O/<arm>.wall`; `wait`; write `$O/guard.txt` (load1 start and end, foreign-run lists at start and end, a final `DISTURBED` or `CLEAN` line; the load ceiling is `MAX_LOAD1`, default 9.0, overridable so the guard can be exercised with a synthetic value); print one summary line. Output root: `/var/tmp/m12013/<rep>/`, never reused.
2.3 Write `$M/site_cost_table.py` (run with `python3 -I`): inputs are the arm stamp files of every rep; checks each file carries seq 0..602 then EOF (604 lines), strictly monotonic times, the rep's `guard.txt` says CLEAN, and the arm's `.rc` is 0 with the same `N passed` line the unhooked arm prints; refuses (rc 2) a rep whose guard file says DISTURBED. Per rep and site: `raw_cost = owner_interval - median(the two non-owning arms' intervals)` (unclamped), `cost = max(0, raw_cost)` (as ruled, F2), `noise_s = |nonowner1 - nonowner2|`; a site is flagged when `cost < noise_s` or its median non-owner interval exceeds 5 s (the unconditional chunks, for example the glob-rate `chk` block that sits inside one owned interval). Also per site: `row` (the last argument of the static `mutate`/`ow_mutate` call line) and `others_live` (how many other arms' EOF stamps are later than this site's start). Per arm, `unconditional_s = arm wall - sum of owned raw_cost`, so the predicted wall closes by construction. Per-site values are the median across reps. Writes `$M/site_costs.tsv` (header lines `# tree=<sha>`, `# DECLARED_TOTAL=602`, `# unconditional_s a=<> b=<> c=<>`, then `site<TAB>arm<TAB>row<TAB>cost_s<TAB>raw_cost_s<TAB>noise_s<TAB>flag<TAB>others_live`). `--selftest` runs the hand-computed golden of AC4.
2.4 Run `python3 -I $M/site_cost_table.py --selftest`; run the two repo ratchets over the new `.sh`: `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/grep-q-pipe-guard.test.sh` (both must exit 0 before the first commit, with the new file tracked via `git add -N`; fix with a guarded absolute operand and here-strings, not suppressions).

### Phase 3 - Site-cost runs (long: about 25 min each, serial between reps)

3.0 Smoke (short): in a fresh hooked clone run one standalone arm with `--rows 1-1`. Skipped sites still reach the gate, so the stamp file must hold exactly 604 lines (0..602, EOF), strictly increasing, the arm must exit 0, and the hooked and unhooked arms must print the same `N passed` line. Leave the smoke directory in place if the removal hook refuses it.
3.1 `TREE=$(git rev-parse HEAD) bash $M/site_cost_run.sh r1`, then `r2`. Start each with the guard; do not run anything heavy on the host meanwhile (`nice -n 10` is already applied). Wait with a Monitor on the `$O/*.rc` files, never a sleep chain, and test the Monitor filter against the first real line first.
3.2 Run `r3` only if any arm's measured wall differs more than 15% between r1 and r2 (ruling F2). Replace a DISTURBED rep rather than averaging it in.
3.3 Copy to `$M/raw/` the stamp files (`<rep>.<arm>.stamps.tsv`, about 600 rows each), `guard.txt`, `<arm>.rc`, `<arm>.wall` and the arm's `N passed` line, so the committed table is rebuildable from committed files; put the per-rep summary lines into `summary.txt` as `rep <r> ... CLEAN|DISTURBED`.

### Phase 4 - Table, validation, paper checks

4.1 `python3 -I $M/site_cost_table.py $M/raw $M/site_costs.tsv` (after Phase 3). The validity assertions (602 rows, ranges tile 1..602, every cost >= 0, header complete) live once, in `site_cost_whatif.py --check`, which `site_cost_whatif.py` also runs before it models anything.
4.2 Validation (rulings F2, R1, R2). Predicted wall of arm k = `unconditional_s` plus the sum of its `raw_cost`. For the comparison with the archived pooled walls (t1: a 1487, b 530, c 525 s; control2: 1364, 525, 513 s) subtract the three Phase 1.2 ordinals from arm c's prediction, because those readings ran 599 sites (if their summed cost is under 1% of arm c, skip 1.2 and say so). Fit the contention scale on arms b and c only (their runs overlap the other arms throughout) and require their two measured/pooled ratios within 10% of each other. Apply that scale only to the part of arm a's cost accrued while another arm was live (`others_live` > 0); the part with no other arm live is taken at ratio 1.0. Require a's predicted wall within 15% of the archived 1487 s, and print a's alone-seconds and overlapped-seconds separately in `summary.txt`. List every flagged site (`cost < noise_s`) in `summary.txt`; if the flagged sites hold more than 20% of any arm's raw site-seconds the table is noise-dominated for that arm. Split-half test (the closure of `unconditional_s` makes every arm's total agree by construction, so totals cannot validate the distribution): cut each arm's owned sites into 10 contiguous blocks and compare the block sums of r1 and r2; if any block holding at least 5% of the arm's raw site-seconds differs by more than 20%, or the blocks' rank order differs, the table is not stable. Also flag any site whose r1 and r2 costs differ by more than max(2 s, 25%) and apply the 20% noise-dominated rule to those flags too. Any failed test: `summary.txt` says "table does not support a rebalance" and Phase 5 is skipped.
4.3 `python3 -I $M/site_cost_whatif.py $M/site_costs.tsv $M/launch_order.t1.tsv $M/launch_order.control2.tsv` writes `$M/whatif.out.txt`. Model: list schedule, width 4, lane tokens ignored, the `*` suite removed (it runs last and alone), launch order from the committed launch-order files; jobs launch in `start_s` ascending order (file order of `suites.tsv` is completion order and is 22% off); baseline assertions: the model reproduces t1's pool end (1845 s pool-relative) and `approval-guard1-mutation` start (765 s) within 15 s, and, fed t1's launch order with control2's walls, control2's `approval-guard1-mutation` end (1658 s) within 15 s; else the check is void. The split search uses `raw_cost` over all contiguous splits (about 181k), run twice: with and without the boundary pristine-row charge (the first dispatched site of each `row` in an arm pays one pristine-row run, `PRISTINE_OK` in the test file; estimate it per row from the table, and for a row with a single site use the largest pristine cost observed). Report, for the ordering on main today (gating) and for start-first of `approval-guard1-mutation` (information): baseline pool end, best split, nominal gain, and the paired robustness result: for each of the 81 combinations of {-15%, 0, +15%} per arm times {666, 880, 1080} s for `approval-guard1-mutation`'s wall (the archived readings: 666 s from the #12263 issue body, 880 s control2, 1080 s t1; record that in `summary.txt`), apply the perturbation identically to the baseline and the candidate split (scale factors attach to the baseline arm that owns each site) and take the paired difference of pool ends (minimum over the 81). Verdict line `GATE: PROCEED` only if, in BOTH pristine-charge runs, the nominal gain is at least 60 s in the gating ordering (the brief's 30 s is the floor for even considering a split; any gain below 60 s is `NO-REBALANCE`, ruling R4), the minimum paired gain over the 81 is at least 0 s, and 4.2 passed; any flip or failure is `GATE: NO-REBALANCE`; a split whose gain exists only under start-first prints `GATE: NO-REBALANCE (start-first only)`. The script also prints the packing floor (sum of walls / 4) and floor plus cold derive, computed from the committed rows, and runs `--check` first. `--selftest` covers the verdict logic (AC12).
4.4 #12263 pricing (paper only, ruling F4), same script: start-first of `approval-guard1-mutation` alone, and of the three long suites (`approval-guard1-mutation`, `argv-bearer-sweep`, `destroy-ask-mutation`), each as the modelled pool end and its gap to the floor; name the suite that ends the run in each reading from its `suites.tsv` row and quote its registration position (`bash scripts/test-all.sh --enumerate-commands` order). Reap latency: check in source (`_pj_reap`, the verdict print) what `(NNNms)` measures. If it is measured to the rc file, `summary.txt` gets one paragraph with the median and maximum of `(done stamp - started stamp) - own wall` over the two readings; if it is measured to the reap, `summary.txt` says the eager-reap lever is unpriceable on committed rows. No separate file.
4.5 Write `$M/summary.txt`: method, the per-rep guard facts, the validation ratios, the verdict line, the floor arithmetic, the top 20 sites by cost, and the explicit non-claims (the table is a standalone-contention measurement scaled to the pool; no pooled gain is claimed).

### Phase 5 - Conditional: land a rebalance (only if `GATE: PROCEED`)

5.1 Re-split from the script's best split: edit the three `run_suite` argv lines in `scripts/test-all.sh` (the `ci-pr-affected-replay-{a,b,c}` registrations), the three rows of `scripts/ci-oracle-lane-suites.txt`, the `sed 's|--rows 1-193|...|'` argv-drift mutant in `scripts/ci-oracle-lane.test.sh`. `DECLARED_TOTAL` stays 602 and the arms stay three.
5.2 Gates: `bash plugins/soleur/test/scripts-shard-totality.test.sh`, `bash scripts/ci-oracle-lane.test.sh`, `bash scripts/test-all-corpus-weight-budget.test.sh`, and the manifest regeneration as a no-diff check (a diff in the shard-leg or durations TSVs is reported, not hand-edited). Editing the runner makes the local gate degrade to the full battery (`AFFECTED_FALLBACK reason=runner-changed`) and CI is then the gate.
5.3 Cold readings (ruling G1), adapted `measure.sh` / `derive.sh` copied from the archived spec into `$M` with `SRC_WT`, the output root and the default `PIN` parametrized (pin `7af192071d`, expected `selected=162 of=742`, check `derive.sh` prints it): `bash $M/measure.sh c1 <base-sha>` then `bash $M/measure.sh t2 <rebalanced-sha>`; the read of the runner's own banners in the first 60 s must show `[parallel] mode engaged` (abort and replace the reading if a `LOCK_WAITING` or `serial fallback` banner appears); `SOLEUR_PJ_FIFO` unset. Keep rule: land if T2 pool phase <= C; if T2 exceeds C by 0 to 50 s or either reading looks disturbed, run `c2` and land only if T2 <= mean(C, C2) + 30 s; if T2 exceeds C by more than 50 s, revert Phase 5.1 and say "not landed". The failure set must equal the known clone artifact (`apps/web-platform [repo-wide+component]`). The PR may say "no regression measured" and nothing stronger.

### Phase 6 - Records and hand-off

6.1 Run the checks of Phase 2.4 again over the final tree; run `git diff origin/main --stat` and compare with the AC2 allow-list.
6.2 Comment on #12263: the site-cost table location, the priced paper results (start-first and eager-reap), the named run-ending suite and its registration position, the CTO ruling for the follow-up PR (hand-listed hoist, margin 100 s, ABBA, separate PR), and the archived reading harness path (`knowledge-base/project/specs/archive/20261107-113626-feat-one-shot-12231-star-suites-last/measurements/`). `Ref #12013`.
6.3 Comment text for #12231 (posted at merge): the 40 s reading against the 57 s spread, the structural evidence, the F1 ruling; close #12231 after merge (post-merge task, `gh issue close 12231 --comment ...`).
6.4 ADR-242 amendment dated 2026-11-07: one paragraph closing Decision 30's open residual per F1 (the structural change is the deliverable; the pool-phase gain is unresolved) with a pointer to `summary.txt`. The rebalance gate (F3) and the follow-up shape (F4) live in `decision-challenges.md` and the #12263 comment, not in the ADR.
6.5 Comment on #12013 (ruling F5): floor arithmetic from the script output, "ordering and splitting recover at most about 300 s of the roughly 1.5 ks gap", the work-reduction levers already named in the issue as the real path, and `budget_seconds=2400` unraised. PR body: `Ref #12013`, `Ref #12231`, `Ref #12263`; no `Closes`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/measurements/rows-range-site-cost-hook.patch`
- `.../measurements/site_cost_run.sh`, `.../site_cost_table.py`, `.../site_cost_whatif.py`
- `.../measurements/site_costs.tsv`, `.../raw/<rep>.<arm>.stamps.tsv`, `.../whatif.out.txt`, `.../summary.txt`
- `.../measurements/launch_order.t1.tsv`, `.../launch_order.control2.tsv`
- `knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement/tasks.md`, `decision-challenges.md`
- Conditional path only: `.../measurements/measure.sh`, `.../derive.sh` (adapted), reading summaries

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (append an amendment)
- Conditional path only: `scripts/test-all.sh` (three argv lines), `scripts/ci-oracle-lane-suites.txt` (rows 45 to 47), `scripts/ci-oracle-lane.test.sh` (argv-drift mutant)

## Acceptance Criteria

Pre-merge (PR):

- [ ] AC1 `python3 -I $M/site_cost_whatif.py --check $M/site_costs.tsv` exits 0 (602 data rows, ranges tile 1..602, every cost >= 0, header names tree SHA, `DECLARED_TOTAL=602` and each arm's `unconditional_s`), and `python3 -I $M/site_cost_table.py $M/raw <scratch>/rebuilt.tsv && cmp <scratch>/rebuilt.tsv $M/site_costs.tsv` exits 0 (the committed raw set reproduces the committed table). Run at `$M` before the archive step and again at its archived path.
- [ ] AC2 `git diff origin/main --name-only | grep -vE '^knowledge-base/project/(specs|plans)/archive/[0-9-]+(-feat-one-shot-12013-site-cost-measurement|-chore-measure-replay-site-costs)|^knowledge-base/project/(specs|plans)/(feat-one-shot-12013-site-cost-measurement/|2026-11-07-chore-measure-replay-site-costs)|^knowledge-base/engineering/architecture/decisions/ADR-242-|^knowledge-base/project/learnings/'` prints nothing (the pipeline archives the spec dir and plan under `archive/` at ship, writes `session-state.md`, and may add a learning; `knowledge-base/INDEX.md` is gitignored), and `git diff origin/main --stat -- scripts plugins .github .soleur-test-gate.json` is empty (`budget_seconds` stays 2400).
- [ ] AC3 `grep -c '^GATE: ' $M/summary.txt` prints 1; `grep -cE '^rep r[123] .*(CLEAN|DISTURBED)' $M/summary.txt` equals the number of reps run; the validation ratios, a's alone/overlapped seconds, the packing floor and floor plus cold derive are present and were written by the scripts (each line carries the script name as prefix), not typed.
- [ ] AC4 `python3 -I $M/site_cost_table.py --selftest` exits 0 against a hand-computed golden (literal expected costs, not generator-derived): distinct costs at sites 1, 193, 194, 386, 387 and 602 (owner boundaries), unequal non-owner intervals, head (0 to 1) and tail (602 to EOF) landing in `unconditional_s` and never in site 1 or 602, a negative `raw_cost` kept unclamped, a 3-rep median with one outlier, and `unconditional_s` closure (wall minus sum of owned `raw_cost`); and these mutants go RED: owner range shifted by 1, stamp mapping k to k-1, head folded into site 1, clamped `raw_cost`, mean instead of median. A DISTURBED guard file is refused (rc 2).
- [ ] AC5 Each rep's guard file (`guard.txt`, written by `site_cost_run.sh`) records load1 start and end and the foreign-run lists; `site_cost_table.py` refuses to read a rep whose guard file says DISTURBED (load1 start above 9.0, or a foreign run listed at start or end), and `summary.txt` lists every rep with its verdict. The criterion is a property of the committed files, not of the machine at review time.
- [ ] AC6 With the new `.sh` tracked (`git add -N $M/site_cost_run.sh` first; the ratchets read tracked files only), `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/grep-q-pipe-guard.test.sh` exit 0.
- [ ] AC7 `gh issue view 12263 --json comments --jq '.comments[].body' | grep -c site_costs.tsv` is at least 1, and `gh issue view 12013 --json comments --jq '.comments[].body' | grep -c budget_seconds` is at least 1 (comments of 6.2 and 6.5).
- [ ] AC8 `gh pr view --json body --jq .body | grep -E '^(Closes|Fixes|Resolves)'` exits 1, and the lines `Ref #12013`, `Ref #12231` and `Ref #12263` are present.
- [ ] AC9 ADR-242 carries a 2026-11-07 paragraph stating the F1 disposition and no measured figure beyond a pointer to `summary.txt`.
- [ ] AC10 Conditional: if `GATE: PROCEED`, AC2 is replaced by the Phase 5 file list, the three gates of 5.2 exit 0, and the G1 keep rule is recorded with both readings' guard facts; the PR claims "no regression measured" only.
- [ ] AC12 `python3 -I $M/site_cost_whatif.py --selftest` exits 0: a synthetic table with a clear split prints `GATE: PROCEED`; a flat table prints `GATE: NO-REBALANCE`; a start-first-only gain prints `(start-first only)`; a pristine-charge flip prints `NO-REBALANCE`; the minimum paired gain over the 81 combinations is hand-checked on a 3-arm toy.

Post-merge (agent-run, ship Phase 7):

- [ ] AC11 `gh issue close 12231 --comment` with the 6.3 text; `gh issue view 12013 --json state` still OPEN.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-242 (no new ADR): one paragraph dated 2026-11-07 closing Decision 30's open residual per ruling F1. It is a task in Phase 6.4, not a deferred issue. The test of the gate: an engineer reading ADR-242 today would find the `*`-last gain "unresolved" with no closing rule; the paragraph closes that.

### C4 views
No C4 impact: read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`; the local test runner, its fixtures and git are not modeled as actors, systems, containers or access relationships, and a grep for `test-all`, `affected`, `local gate` and `replay` finds only the unrelated Redis `replay buffer` and `affected (blind)` prose. No cardinality in edge prose is touched.

### Sequencing
Not applicable: nothing is gated on a later slice.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings F1 to F5 and G1 to G3 (see `decision-challenges.md`): close #12231 on the structural decision; measure site cost by concurrent hooked arms with a ratio-validated scale; replace the 1.5x bound with a robustness gate; paper-only for #12263; zero cold readings unless a split clears the gate; `Ref #12013` only. No other domain is relevant: no user-facing surface, no data, no spend.

## Test Scenarios

1. Hook transparency: the same arm with and without the patch prints the same `N passed` line (Phase 3.0).
2. Builder correctness: synthetic stamps with known costs are recovered within 1 ms (AC4).
3. Model validity: the what-if reproduces t1's pool end and approval start within 15 s, and control2's approval end within 15 s from t1's order, before any verdict (4.3).
4. Gate direction: a synthetic table with a split gaining 60 s or more prints `GATE: PROCEED`; the measured table's verdict is whatever it is, recorded as printed.
5. Disturbance: the `--selftest` feeds `site_cost_table.py` a synthetic rep whose guard file says DISTURBED and asserts the builder refuses it (rc 2); the guard function in `site_cost_run.sh` aborts with rc 3 on a synthetic load value passed through an override variable.

## Verification Record (observability schema not triggered)

The plan Phase 2.9 trigger set is not met: the Files lists touch no `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts` file and introduce no service, cron or workflow. The committed `summary.txt` is the discoverable record of every reading's guard facts.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with the scope-out reason.
- The standalone arms contend less than the pool; the table is relative cost, valid for a rebalance only after the ratio test of 4.2. Do not quote it as pooled seconds.
- Non-archived `.sh` files in the feature spec dir are swept by two ratchets (see Research Insights); run both before the first commit, and keep Python and `.patch` data out of those two sweeps' reach by extension, not by suppression.
- `/var/tmp/m12231` is volatile: Phase 1 first.
- Site cost depends on where the split boundaries fall: the first dispatched site of each `row` per arm pays a pristine-row run (`PRISTINE_OK`), and the glob-rate `chk` block (about 490 lines) sits inside one owned interval; the table carries `row`, `raw_cost`, `noise_s` and flags for that reason.
- The local gate for this PR is short on the zero-rebalance path (no runner edit); on the conditional path it degrades to the full battery and CI is the gate.
- `git commit` in this repo is blocked when the same call expands a variable or runs `bash -c`; commit with literal paths in a call of its own.
- End a turn that waits on a background reading with a plain `Paused:` line.
