---
title: "chore: measure whether the JOBS=1 stopgap on the main health monitor can be removed (grep -q series, Item I)"
type: chore
date: 2026-10-16
slug: grep-q-series-item-i-jobs1-stopgap
branch: feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap
issue: 7432
lane: cross-domain
---

# chore: measure whether the JOBS=1 stopgap on the main health monitor can be removed (Item I)

> **Review-round supersession (2026-10-18, 10 seats plus CTO rulings; see `decision-challenges.md`).** Where this plan and the shipped
> tree differ, the tree wins: the `measure/` scripts were cut (queries live in `evidence.md`); the probe now proves `-P K >= 2` from each
> counted run's log, counts strikes (one tolerated, two exit 5) with a committed `JUDGED_REPRODUCING_RUNS` list instead of exiting 5 on any
> non-allowlisted RED, and reads the log with `--allow-escape-sequences`; `earliest=` is set before merge to 2026-10-19T00:00:00Z or later
> (not "the merge time" after it); #7376 is unchained (its probe is deleted); the monitor is pinned to `runs-on: ubuntu-24.04`; guard (12b)
> also catches quoted `"JOBS"` keys; per-suite bounds were widened in a separate PR merged first.

## Enhancement Summary

**Deepened on:** 2026-10-16
**Review and research agents used:** DHH, Kieran and code-simplicity (plan-review); architecture-strategist, test-design-reviewer, git-history-analyzer (deepen); CTO agent (rulings and a re-consult on corrected figures); repo-research, learnings-researcher, functional-discovery (plan).

### Key improvements

1. The probe's soak window is now the sweeper-supplied `SOLEUR_FT_EARLIEST` (merge time), so an unrelated edit to the monitor workflow cannot restart the soak or reopen #7432.
2. The sweeper workflow needs `checks: read` for the annotation read (an explicit `permissions:` block makes an unlisted scope `none`); it is a listed edit and the first live sweep after merge is the positive control.
3. The known tag-drift RED no longer blocks the soak (allowlist in the probe), and the dispatch gate now also requires the tests-step log to show the nested runner was skipped.
4. Guard 1 gained the location and value axes and a fail-closed trailing-comment row; Guard 2 gained the window, branch, list-limit, precedence, exit-78 and cross-check rows, with a strict stub `gh`.
5. Repo costs the plan had missed are listed: the xtrace-refusal baseline line, the fixture-relative-assert baseline, `MIN_ASSERTIONS`, `PJ_TRIPLES`.
6. Two measurement corrections: 81 of 269 (30%) killed infra steps, and the paired comparison has only 3 informative pairs once censored steps are excluded.

### New considerations discovered

- The monitor's infra step runs after a 110-minute tests step on a non-fresh runner, which the fresh-runner legs do not cover; the dispatches reproduce that sequence.
- The `infra-validation.yml` "fixed at source" wording is only partly supported (commit 532a6b3480 via #7423); #7376 is still open.

## Overview

Item I of the grep -q pipe-guard series (tracker #9217) asks one question: can the two `JOBS: 1`
pins on the suite steps of `.github/workflows/main-health-monitor.yml` come off. The answer is
decided from run data pulled from GitHub, and the result is either a PR that removes the pin with
the measurement as evidence, or a record on #9217 that Item I is not fixed, with the measured reason
and a `Ruled by CTO agent` line.

This plan did the measuring first (2026-10-16, figures below, commands in `## Measurement`), took
the evidence bar and the option choice to the CTO agent, and the CTO ruled **Option D: remove the
infra-step pin only, keep the tests-step pin, split check (12), and gate the removal on two
dry-run dispatches of the real workflow at the default width**. If either dispatch fails the bar,
the work phase takes the not-fixed branch (Phase 5b) instead. The tracker #7432's "deadlock"
premise is falsified by the data, so its probe-job prescription is cut.

## Research Reconciliation — Spec vs. Codebase

The brief and #7432 carry claims written on 2026-08-11. Each was verified against the repo and GitHub.

| Claim (source) | Reality (how verified) | Plan response |
|---|---|---|
| Removal is deadlocked: "the only place CI runs the runner at default `-P` is the monitor itself, which is pinned" (#7432 body) | FALSE. `infra-validation.yml` `deploy-script-tests` runs `run-registered-suites.sh` unpinned on the same hosted 4-core class; each leg log prints `Running N registered infra suite(s) (shard k/4 ...) with -P 4`. 688 leg executions on push-to-main since 2026-09-25 (M2) | Probe job at `-P 4` is cut (CTO Q2). Existing legs are the CI-grade evidence |
| Add a `continue-on-error` non-issue-filing probe job at `-P 4` (#7432 item 1) | Not needed (above). The workflow already has a non-filing measurement path: `workflow_dispatch` input `dry_run` gates the filer, the closer and the Sentry check-in (`!inputs.dry_run` on each) | Evidence by two branch dispatches with `dry_run=true`, no new workflow surface |
| Remove both `JOBS: 1` pins (#7432 item 2; brief) | The tests-step pin is a no-op for the runner on main: in a completed tests step the nested infra runner prints `[skip] apps/web-platform/infra/run-registered-suites.sh (not_in_diff)` and never starts (run 37121488194 log; none of the 300 `main` monitor logs carries a nested `Running N ... with -P` line before the infra step). The tests-step timeouts (129 of 300) have a separate cause, tracked in #9410 | CTO Q3: remove the infra pin only; keep the tests pin (it still covers a branch diff touching `apps/web-platform/infra/`) |
| Delete check (12) of `main-health-monitor-workflow.test.sh` (#7432 item 3) | Check (12) asserts the pin on both steps; it is the reintroduction guard added by commit 3bffffcbe7 (merged in squash f13f206a15, #7371) after the monitor's own run 31367748528 filed the spurious P1 #7386 (the suite did not catch its own regression) | CTO Q5: split it: tests step stays asserted, infra step asserted ABSENT with an evidence-pointing message |
| `scripts/followthroughs/jobs1-stopgap-7432.sh` exits 2 while `JOBS: 1` is on main and closes the tracker when gone | TRUE (read the script: `grep -c 'JOBS: 1'`, PASS at zero). With Option D one pin stays, so it would never close #7432 | Rewrite the probe to the soak criterion (Phase 3) |
| Gated on "#7376's per-suite diagnostics producing at least one attributed CI failure, or a clean soak" | Diagnostics have produced 88 attributed `--- RED: <suite> (rc= elapsed=)` headers across 75 failed legs (M3). Attribution says deterministic or isolated, none shown parallel-only (M4) | Gate satisfied on the "attributed CI failure" arm |
| Stopgap "costs wall-clock on every run" (#7432) | Understated. At the current 179 suites the sequential infra step no longer fits its 3600 s ceiling: 81 of 269 infra steps that could deliver a verdict (30%) were killed at the ceiling and delivered none (M1) | This is the benefit side of the decision |
| `infra-validation.yml` says the -P 4 flake was "the tmpfs/live-tree collision class (fixed at source)" | Partly supported: the live-tree collision fix is commit e2066f780c (a frozen snapshot instead of the live tree), on main inside squash 532a6b3480 (PR #7423, merged 2026-08-11) together with the per-suite RED diagnostics; the tmpfs half is the `TMPDIR=/var/tmp` default (2091b655ed). #7376 itself is still open and that commit calls its RED a capacity failure, not contention | Cite 532a6b3480 in the comment correction; do not describe the flake as closed |
| `infra-validation.yml` and ADR-252 say "main-health-monitor keeps JOBS:1" | True today, false after this PR for the infra step | Comment-only corrections in Phase 2 |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #7432 (OPEN, label `follow-through`, directive present), #7376 (OPEN; its probe
`suite-runner-flake-7376.sh` closes it only when #7432 is CLOSED), #9217 (OPEN tracker; latest
comment is the Item G merge record, 2026-10-16T16:37Z), #9457 (OPEN sentinel tracker "terminated
before it could report"), #9410 (OPEN: shard the tests step), PR #10459 (draft, this branch). Cited
files exist on the branch: the workflow (the two `JOBS` env lines and the comment block above the first), the workflow test (check (12), the "JOBS=1 on BOTH suite steps" section), the probe. ADR corpus: ADR-252 mentions the pin (one sentence, no decision about it);
no ADR decided "keep JOBS=1", so no rejected-alternatives conflict. Stale: the #7432 deadlock
premise and the "both pins" prescription (see table).

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

1. The monitor's infra step delivers a verdict on every run (it is not killed by its ceiling).
2. The monitor does not file a spurious P1 for a suite that only fails because of parallel contention.
3. The decision rests on parsed fields from run data, each instrument shown against a positive and a negative control.
4. The tracker closes by itself when the soak holds (the repo convention for time-gated closure).
5. Nothing reintroduces the pin silently, and nothing restores a pin without the evidence.

Cut List (mechanism, property, what already covers it):

- `continue-on-error` non-filing `-P 4` probe job (#7432) -> property 2 evidence -> the 688 existing `deploy-script-tests` leg executions plus the workflow's own `dry_run` dispatch.
- Removal of the tests-step pin -> property 1 -> buys nothing: the nested runner is skipped there. Kept.
- Deleting check (12) -> property 5 -> split instead, so the guard against reintroduction survives.
- A different width (`JOBS: 2`) -> property 1 -> no measurement supports it; fallback only (CTO Q3).
- Editing the issue-filing logic -> property 2 -> the named `RED <suite>` lines already make triage and revert cheap (CTO Q4).

### Relevant institutional learnings

- `knowledge-base/project/learnings/2026-08-09-the-monitor-reported-success-and-i-read-the-field-that-cannot-say-otherwise.md`: read the runner's verdict, not a conclusion field; the contention variable, not `-P`; removing the pin once filed a spurious P1 (#7386).
- `knowledge-base/project/learnings/test-failures/2026-10-16-i-counted-a-line-printed-for-every-suite-and-two-rulings-rested-on-it.md`: parse the field that carries the verdict; run a known-0 and a known-1 control first.
- `knowledge-base/project/learnings/2026-10-02-a-monitor-verdict-read-from-a-line-the-runner-prints-only-conditionally.md`: ceilings were derived from right-censored durations; dispatch from the branch.
- `knowledge-base/project/learnings/2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md`: a zero-failure sample bounds the rate by about 3/n only; decide the sample size before measuring.
- `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: a registration-only `scripts/test-all.sh` edit is bounded; any other edit of it degrades the author's gate to the full battery.

### Domain Review input

CTO agent consulted (see `## Domain Review`). Functional-overlap check against the community
registries: nothing relevant (3 of 3 registries answered; candidates were tied to OpenShift Prow,
JUnit quarantine dashboards or Cypress).

## Measurement (done at plan time; the work phase re-runs it)

All raw data lives under `/var/tmp/item-i/` (never `/tmp`). Re-run everything with one command; it
prints the figures and fails loudly when a control fails:

```bash
ITEM_I_DIR=/var/tmp/item-i-work bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/measure/run-all.sh
```

`measure/run-all.sh` pulls the data, `measure/extract-monitor-facts.sh <run_id> <job_id>` extracts
per-run log facts, and `measure/analyze.py` prints M1 to M4 after its CONTROLS block. The verdict
fields and the controls:

| Instrument | Field parsed (exact) | Positive control | Negative control |
|---|---|---|---|
| Monitor verdict | check-run annotation titled `main-health-outcomes`, message `SOLEUR_MAIN_HEALTH tests=<x> infra=<y>` (never the run or job `conclusion`: `continue-on-error: true` pins it to `success`) | run 38897624648 reads `tests=failure infra=failure` (its log shows the runner `[KILLED] ... 3609001ms`) | 119 runs read `tests=success infra=success` and carry no timeout annotation; 23 cancelled runs read `ABSENT` |
| Ceiling kill | annotation message `The action 'Run infra suites' has timed out after 60 minutes.` (and the `Run test suite` form) | run 38897624648 carries both | every `success success` run carries neither (asserted in `analyze.py`) |
| Infra width and size | log line `Running N registered infra suite(s) [(shard k/4 of M) ]with -P W` after the `TEST_GROUP: infra` env dump | infra step of run 38897624648: `179 ... -P 1`; a leg log: `58 ... (shard 3/4 of 146) with -P 4` | tests-step half of the same log: no such line (0 of 300 logs have one) |
| Suite RED | log lines `--- RED: apps/web-platform/infra/<suite> (rc=N elapsed=Ns ...)` and `^RED  <path>` | leg log of job 108669589945 names `cutover-inngest-workflow.test.sh` rc=1 | a green leg log names none |
| Leg verdict | job `conclusion` of `deploy-script-tests (k/4)` (a plain job, no `continue-on-error`, so the conclusion is honest here) | failed legs carry a RED header | `success` legs carry none |

Figures (taken 2026-10-16; re-derive, do not trust):

- **M1 monitor history** (300 runs on `main`, 2026-08-03 to 2026-10-16, all `workflow_dispatch` from the Inngest cron; the monitor runs the infra step at `-P 1` in 269 of them, the other 31 have no verdict). Infra step: 171 ok, 81 killed at the 60-minute ceiling, 17 RED without a timeout, 31 no verdict (cancelled or early); so 81 of the 269 steps that could deliver a verdict (30%) were killed. By month: Aug 83 ok / 1 red / 1 timeout; Sep 47 ok / 8 red / 65 timeout; Oct 41 ok / 8 red / 15 timeout. Infra suite count 93 -> 179. Uncensored infra elapsed: median 3115 s, max 3572 s (n=49) against 3600 s. Tests step: 129 of 300 killed at its 110-minute ceiling; unaffected by the infra pin.
- **M2 `-P 4` in CI**: `deploy-script-tests` legs on push-to-main since 2026-09-25: 172 runs, 688 leg executions: 609 success, 75 failure, 4 cancelled. Median sum of the four legs' runner steps (n=40 runs): 1757 s for about 175 suites, so a single `-P 4` pass fits the ceiling with margin.
- **M3 leg REDs**: 88 suite REDs (86 rc=1, 2 rc=124). 45 of the 75 failed legs are the deterministic `cloud-init-inngest-bootstrap` tag-drift guard (also RED in the monitor at `-P 1`). Leaving out the 3 runs that have a cancelled leg: chained across adjacent pushes 61 suite-events; isolated single-push suite-events 23 over 169 runs (13.6% per run, an upper bound: a run with two isolated suites counts twice and one-commit regressions are included).
- **M4 paired same-sha** (shas run by both the monitor at `-P 1` and the legs at `-P 4`; a ceiling-killed monitor step is left out because its RED set is right-censored, and so is a run with a cancelled leg): 15 paired shas, of which only 3 had a RED in either arm (the informative pairs); 0 suites RED at `-P 4` that were clean at `-P 1` and 0 the other way. A zero over 3 informative pairs is weak evidence by itself.
- Instrument caveats: `analyze.py` reports isolated suite-events per push run (a run with two isolated suites counts twice), adjacency and the paired set skip runs that have a cancelled leg, and it reports how many of the 21 paired shas had at least one RED in either arm (a zero over few REDs is weak).
- Sample-size note: M4 has 15 paired shas but only 3 informative ones, so a zero bounds the paired parallel-only rate near 100% (3/3 is no bound at all); M4 is a consistency check, not evidence of safety, which is why the CTO bar rests on the two dispatches, the revert trigger and the harm comparison.

The committed instrument was validated by re-running it from scratch (`ITEM_I_DIR=/var/tmp/item-i-main`, `main` branch only) at plan time; it printed `CONTROLS OK` and the M1 to M4 figures above.

Window and ceiling caveats: the 90-day log retention reaches 2026-07-18, so the 300-run window is
fully readable now; a later re-run drops its oldest rows. M3 is push-to-main only: `infra-validation`
has no `merge_group` trigger, so merge-queue runs are not a source of this evidence.

## Decision (technical ruling)

Ruled by CTO agent, 2026-10-16 (full rulings in `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/decision-challenges.md`):

- Statistical sufficiency is not the basis (re-ruled on the corrected figures: only 3 of 15 usable paired shas are informative, so M4 bounds nothing). The decision rests on the two dispatches, the harm comparison (81 of 269 infra steps, 30%, killed at the ceiling with no verdict, against a parallel-only spurious-P1 rate bounded at 13.6% per run that also counts real regressions) and a one-line revert.
- The #7432 deadlock premise is falsified and the probe job is cut.
- Option D: remove the infra-step pin only. Option C (not fixed) is wrong on this data unless the dispatch gate fails; Option E (`JOBS: 2`) is out of scope, a fallback only.
- Work-phase gate before removing: two `dry_run=true` dispatches of the real workflow from this branch, reproducing the real sequence (tests step, then the infra step on the same non-fresh runner; the workflow's `dry_run` input gates only the filer, the closer and the check-in, so the tests step still runs in full and the dispatch is full evidence on runner state). Per dispatch the infra step must show the `-P 4` breakdown line, elapsed at most 2400 s (above 3000 s is a hard fail; between 2400 and 3000 s is ambiguous and triggers a third dispatch), no timeout annotation, no `[KILLED]` or OOM-killed child, and no RED other than the known deterministic `cloud-init-inngest-bootstrap` tag-drift guard (only if main has it at that sha). A non-deterministic RED in either dispatch, or elapsed above 3000 s, keeps the pin and records Item I as not fixed. A third dispatch is added only for an ambiguous result, not by default.
- Revert trigger (first 12 scheduled monitor runs, about 3 days): two or more REDs that do NOT reproduce, or any infra step ceiling-killed that was not killed before. A RED reproduces only if the same suite is RED at the same sha in an `infra-validation` run, or a rerun of that suite at `-P 1` also fails. Revert early if any single non-deterministic RED shows in the first 3 runs. The tests step's own kill rate (129 of 300, 43%) is a separate cause (#9410) and is not counted. The followthrough directive states the trigger together with the caveat that, at the 13.6% upper bound, it would fire about half the time only if every isolated event were contention-shaped (M3 cannot establish that), so a revert is not read as a failure of the analysis. Recorded on #7432 (stays open until the soak ends) and in the Item I entry on #9217.
- Check (12) is split, not deleted.

## Implementation Phases

### Phase 0: re-measure (work phase, first)

1. Run the `## Measurement` command with `ITEM_I_DIR=/var/tmp/item-i-work`. The CONTROLS block must print `CONTROLS OK`; if it asserts, stop and fix the instrument before reading any count.
2. Compare M1 to M4 with the plan-time figures. A material change (a suite RED at `-P 4` in a paired sha that was clean at `-P 1`, or M1 infra timeouts near zero) goes back to the CTO agent with the new data before any edit. Otherwise continue.

### Phase 1: guard first, then the pin-removed edit, then the dry-run gate

1. Write Guard 1 rows 1 to 5 and P1 first in `plugins/soleur/test/main-health-monitor-workflow.test.sh` (check (12) lifted into `check_jobs_pin(text)`, (12a)/(12b) as the two real-text verdicts) and watch (12b) go RED against the current workflow.
2. Edit `.github/workflows/main-health-monitor.yml`: delete the `JOBS: 1` line of the infra step (the one under `TEST_GROUP: infra`) and its pointer comment `# See the JOBS note on the tests step above.`; keep the tests-step pin; rewrite the long comment block above the tests-step pin so it states (a) the tests step stays pinned, why (a branch diff touching `apps/web-platform/infra/` nests the runner there; node-gyp reads `JOBS` as `make -j`), and (b) the infra step runs at the runner's default width, citing #7432, the `infra-validation` legs, and the measurement. Do not write the literal token `JOBS: 1` in a comment (the old probe counted it). Add one line to the TIMEOUT BUDGET block that its infra figure was derived at the sequential width and is now over-provisioned (not re-derived here).
3. Commit (guard and workflow together, so the commit is green), verify `git log -1 --format='%an <%ae>'`, push the branch. The branch diff at dispatch time must touch no `apps/web-platform/infra/` path and not `.github/workflows/apply-web-platform-infra.yml` (both arm `_infra_in_diff`, and an undeterminable diff arms it fail-safe), otherwise the nested runner would run in the tests step and warm the workspace (the TIMEOUT BUDGET block records the standalone infra run about 1.9x faster when warm), which would make the infra figure optimistic.
4. Dispatch twice, as ruled: `gh workflow run main-health-monitor.yml --ref feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap -f dry_run=true`; the command prints no run id, so list them with `gh run list --workflow main-health-monitor.yml --branch feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap --event workflow_dispatch --json databaseId,createdAt,headSha` and record the dispatched `headSha`. The second dispatch queues behind the first in the `main-health-monitor-dry-run` concurrency group (`cancel-in-progress` is false), so the two are serial, about 2.5 hours each. The tests step runs first and adds no information, but it makes both dispatches reproduce the monitor's real sequence (a 110-minute tests step, then the infra step), which is the environment the fresh-runner legs do not cover. A dry run files and closes nothing and sends no check-in (`!inputs.dry_run` on the filer, the closer and the check-in). Wait with the Monitor tool, never a background polling loop. The existing workflow carries `workflow_dispatch`, so dispatching a branch ref works; the "new workflow cannot be dispatched pre-merge" limit applies only to a workflow file absent from the default branch.
5. Read each run with the same instruments: `measure/extract-monitor-facts.sh <run_id> <job_id>` for the infra width, size, breakdown and REDs, and the `main-health-outcomes` annotation for `infra=` and `infra_elapsed_s=`. Controls: the facts line for run 38897624648 must read `179 ... -P 1`, and the dispatches must read `-P 4`.
6. Pass bar (CTO, see `## Decision`): in each dispatch the tests-step log prints `[skip] apps/web-platform/infra/run-registered-suites.sh (not_in_diff)` and no nested `Running N ... -P` line (otherwise the dispatch is invalid), and the infra step shows `-P 4`, `infra=success` (or a RED limited to `cloud-init-inngest-bootstrap` while main has the tag drift), `infra_elapsed_s` at most 2400, no timeout annotation, no `[KILLED]`, and no `UNACCOUNTED` line. Elapsed in 2400 to 3000 s is ambiguous: dispatch a third time. A non-deterministic RED or elapsed above 3000 s goes to Phase 5b.

### Phase 2: stale-statement corrections (comment-only)

1. `.github/workflows/infra-validation.yml` (comment block at the `deploy-script-tests` job, the sentence "main-health-monitor keeps JOBS:1 because ..."): state that the monitor's infra step now runs at the default width too, and the tests step keeps its pin.
2. `knowledge-base/engineering/architecture/decisions/ADR-252-infra-suite-registration-is-presence-and-deploy-script-tests-is-a-matrix.md`, the sentence "main-health-monitor keeps JOBS:1 because its failure mode is a spurious P1 page": the same one-sentence correction.
3. `.claude/hooks/grep-q-pipe-guard.test.sh`, the `STILL OPEN (listed, not planned here)` header block: replace "continues with Item I (whether JOBS=1 ... once enough merge-queue runs exist)" by the Item I outcome with its #9217 reference, as the Item G PR did for its own entry (comment-only; the pre-push affected gate does not select this guard, so CI's full battery is the check).
4. Left as is, recorded in the PR body: the clause "(that is why JOBS: 1 is pinned on both steps, not one)" in the comment of `apps/web-platform/infra/run-registered-suites.sh`. It sits under `apps/*/infra/`, an edit there can arm the infra gates and a full-battery degrade for one stale parenthetical; the tests pin it describes still exists, so the clause is half true.

### Phase 3: follow-through probe (CTO Q4)

Rewrite `scripts/followthroughs/jobs1-stopgap-7432.sh` and add `scripts/followthroughs/jobs1-stopgap-7432.test.sh` so the probe decides the soak from data (Guard 2). Write the test first. Mirror the credential-refusal prologue of `scripts/followthroughs/ci-draft-light-soak-9728.sh` (exit 78 under xtrace with `GH_TOKEN` set), delete line 30 of `scripts/lint-shell-trace-credential-refusal.baseline.txt`, and copy `assert_fixture_dir` from `ci-draft-light-soak-9728.test.sh` so the new suite adds no row to `plugins/soleur/test/fixture-relative-assert.baseline.txt` (else regenerate that baseline in the same commit). Register the suite with a single `run_suite` line in `scripts/test-all.sh` (a registration-only edit; the `followthroughs/*.test.sh` glob is not in `SUITE_GLOBS`; a name-stem edge from the test to the probe covers local selection). Run the PJ_TRIPLES recompute recipe (`.claude/hooks/grep-q-pipe-guard.test.sh`, the recipe in its header) before and after: the new files use here-string forms, no `producer | grep -q` join. Add `checks: read` to `.github/workflows/scheduled-followthrough-sweeper.yml` (comment: the annotation read; precedent #8450). After merge, edit the #7432 body directive in place (same script path, `earliest=` set to the merge time, `secrets=GH_TOKEN` kept) and keep #7432 open. The directive text carries: the revert trigger with its definition of "reproduces" and the roughly 50% fire-rate caveat; that cancelled runs are skipped; that the soak is 3.5 days or more; that the allowlisted tag-drift RED counts as clean; and the accepted claim "#7376 closes on 12 clean infra runs while the tests-step pin remains" (repeat it in the #7432 closing comment, not only the PR body). `suite-runner-flake-7376.sh` needs no change (it closes #7376 when #7432 closes). Add a `RETIREMENT:` header line to the probe listing what references it (the #7376 probe's comment, this suite, the `run_suite` line, the baseline line removed here).

### Phase 4: evidence file, ship

1. Commit a compact `evidence.md` under `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/` holding the M1 to M4 figures, the two dispatch rows (run ids, head sha, `infra=`, elapsed, width, RED set) and the exact commands; raw data stays under `/var/tmp`.
2. `decision-challenges.md` rows exist (created at plan time); add any work-phase rulings.
3. After every commit run `git log -1 --format='%an <%ae>'` and expect `Jean Deruelle`; never set or change a git identity.
4. PR body: `Ref #7432` and `Ref #9217` (not `Closes`: #7432 closes through its probe), the figures, the CTO ruling lines, the revert trigger. Then `soleur:ship`, then `soleur:postmerge`.
5. #9217 comment: Item I merged, with the `Ruled by CTO agent, 2026-10-16` lines, the figures, and the revert-trigger window. Do not emit DONE for this PR.

### Phase 5b: not-fixed branch (only if the Phase 1 gate fails or Phase 0 flips)

No workflow edit lands (revert the Phase 1 commit on the branch). Record Item I on #9217 as not fixed with the measured reason (the failing dispatch's run id, the RED suite, rc and elapsed from the `--- RED:` header, or the elapsed figure) and a `Ruled by CTO agent` line from a fresh CTO consult on the new data (a candidate follow-up it may rule: `JOBS: 2` as its own measured change). The PR then carries only the knowledge-base records (`evidence.md`, `decision-challenges.md`); the probe, test and comment edits are not made.

## Files to Edit

- `.github/workflows/main-health-monitor.yml`: remove the infra-step pin, rewrite the comment block, one TIMEOUT BUDGET line (Phase 1).
- `plugins/soleur/test/main-health-monitor-workflow.test.sh`: lift check (12) into `check_jobs_pin(text)`, split into (12a)/(12b), add the in-Python mutation rows, raise `MIN_ASSERTIONS` by the rows added.
- `scripts/followthroughs/jobs1-stopgap-7432.sh`: soak decision (Phase 3).
- `scripts/test-all.sh`: one `run_suite` registration line for the new probe suite (registration-only).
- `.github/workflows/scheduled-followthrough-sweeper.yml`: add `checks: read` to the explicit `permissions:` block (the probe reads check-run annotations; an unlisted scope is `none`).
- `scripts/lint-shell-trace-credential-refusal.baseline.txt`: delete the line for `scripts/followthroughs/jobs1-stopgap-7432.sh` once the probe carries the xtrace refusal.
- `.github/workflows/infra-validation.yml`: comment-only correction.
- `knowledge-base/engineering/architecture/decisions/ADR-252-infra-suite-registration-is-presence-and-deploy-script-tests-is-a-matrix.md`: one-sentence correction.
- `.claude/hooks/grep-q-pipe-guard.test.sh`: comment-only update of the series-state header (Phase 2.3).

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was confirmed with `git ls-files` on this branch.

## Files to Create

- `scripts/followthroughs/jobs1-stopgap-7432.test.sh`: stub-`gh` suite for the probe.
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/evidence.md`: compact evidence.
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/measure/` (`run-all.sh`, `extract-monitor-facts.sh`, `analyze.py`): the re-runnable instruments, created at plan time (kept as the exact commands the brief asked for; only `evidence.md` carries figures).
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-i-jobs1-stopgap/decision-challenges.md`, `tasks.md`.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (200) against each planned path:

- `.github/workflows/infra-validation.yml`: #8735 (notify-main-failure misses cancelled jobs) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate). Acknowledge both: different concerns; this PR edits one comment only.
- `scripts/test-all.sh`: #8659 (33 suites replace test-helpers' EXIT trap) and #7942. Acknowledge: registration-only edit, a different concern.
- The other planned paths: no open code-review issue names them.

## Architecture Decision (ADR/C4)

Skipped: CTO ruling "none worth an ADR; a CI tuning change with a revert trigger". No ownership boundary, substrate, trust boundary or ADR reversal changes. C4 was checked for the actors and systems this touches (GitHub Actions runner, the Inngest cron that dispatches the monitor, the Sentry cron monitor, the `ci/main-broken` tracker): none are added or moved, and no element description is falsified; `plugins/soleur/test/c4-count-parity.test.sh` is expected to stay green (no workflow or monitor count changes).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the monitor is an internal backstop. The operator sees either a spurious P1 `ci/main-broken` comment (a parallel-only flake) or a monitor that again fails to report a broken main.
- **If this leaks, the user's data is exposed via:** no vector; the change touches no credential, data store or user-facing path (a workflow env key, a test guard, a read-only probe).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: a bad outcome is an internal alert-quality regression, bounded by the revert trigger, with no customer-visible effect.

threshold: none, reason: the touched sensitive path (`.github/workflows/infra-validation.yml`) gets a comment-only edit and the monitor workflow edit removes one env key; no user data, credential or request path is involved.

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_MAIN_HEALTH notice annotation (tests=, infra=, infra_elapsed_s=) on every monitor run, plus the Sentry cron check-in
  cadence: every 6 hours (Inngest cron dispatch)
  alert_target: the ci/main-broken tracker (P1 comment or issue) and the Sentry cron monitor main_health_monitor
  configured_in: .github/workflows/main-health-monitor.yml and apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: GitHub issue labelled ci/main-broken (filer step of the monitor workflow)
  fail_loud: the error annotation "Main branch health check did not pass (tests=... infra=...)" and a "CI: main branch tests failing" or "terminated before it could report" tracker title

failure_modes:
  - mode: the infra step is killed at its ceiling after the pin is gone
    detection: annotation "The action 'Run infra suites' has timed out after 60 minutes." and a runner [KILLED] line; the probe exits 1 naming the run (revert trigger 2)
    alert_route: ci/main-broken tracker "terminated before it could report"
  - mode: a contention-shaped suite goes RED at the default width
    detection: "RED  apps/web-platform/infra/<suite>" line and the --- RED --- header with rc and elapsed; the probe exits 5 naming the run and suite
    alert_route: ci/main-broken P1 comment "CI: main branch tests failing"
  - mode: a child suite is OOM-killed under -P 4
    detection: the runner accounting block prints UNACCOUNTED for the suite
    alert_route: ci/main-broken tracker (title branches on UNACCOUNTED)

logs:
  where: GitHub Actions job log of the monitor run (health-check job) and its check-run annotations
  retention: 90 days

discoverability_test:
  command: grep -c -e '::notice title=main-health-outcomes::' .github/workflows/main-health-monitor.yml
  expected_output: 1
```

## Guard Contract

### Guard 1 — check (12b): the infra step carries no JOBS pin, the tests step keeps it

**Property.** In `main-health-monitor.yml` the `tests` step env sets `JOBS` to 1 and no other scope (workflow `env:`, job `env:`, the `infra` step `env:` or its `run:` script) mentions a `JOBS` assignment at all.

**Assembly.** Every place a `JOBS` value can reach the infra runner: the workflow-level `env:`, the job-level `env:`, the `infra` step `env:`, the `infra` step `run:` text (`JOBS=` or `export JOBS`), and an `env:` on a wrapper step. The chokepoint is the comment-stripped text (`stripped`) the file already builds once, which drops WHOLE-LINE comments only (`re.match(r'^\s*#')`; a `#`-anywhere strip is rejected because the file's header records that it truncates `echo "## ..."` and `"B60205"`). The check counts every `JOBS` assignment token in it (expected: exactly one, inside the `tests` env block) with `(?<![A-Za-z0-9_])JOBS\s*[:=]`, so a pin moved to another scope still reds and `JOBS_COUNT` does not match. A trailing `# JOBS: 2` on a code line is therefore counted and reds: that is the documented fail-closed behaviour, pinned by a RED row. (12a) accepts the tests value `1`, `"1"` or `'1'` and nothing else. The existing `step_env_blocks` extractor stays for the two named steps; it runs past a missing `env:` block into the next step, so (12b) also asserts both steps were extracted with their own `env:` block. Implementation: lift the check into `check_jobs_pin(text)` returning the verdicts, call it on the real text for (12a)/(12b), and on in-Python mutated copies for the rows below (the suite is one inline Python heredoc run once against `MHM_WORKFLOW`, so file-swapping the whole 1800-line suite per mutation would also trip unrelated checks and blur attribution). Verify the expected count of one with `grep -c` on the stripped text before fixing it.

**Mutation matrix** (each row is an in-Python assertion pair in the suite, counted by `ok`/`bad`; every row asserts `mutated != original` first, so a mutation that failed to land cannot read as a pass):

| # | Mutation (applied to an in-memory copy of the workflow text) | Expected |
|---|---|---|
| 1 | one pin restored at each of three sites, one site per copy: the infra step env, the job-level `env:`, an `export JOBS=1` line in the infra `run:` | RED (12b) on each copy |
| 2 | location axis: the tests pin deleted and a job-level pin added, so the token count stays 1 | RED (12a) |
| 3 | value axis: `JOBS: 2` in the tests block, and a separate copy with `JOBS: "1"` | the first RED (12a); the second PASS |
| 4a | rename the infra step id so the extractor finds only `tests` (own dispatch: "0 infra blocks checked") | RED (12b reports the missing step, never a vacuous pass) |
| 4b | a copy where the infra step has no `env:` block | RED (12b) |
| 5 | a trailing `# JOBS: 2` comment on a code line (the documented fail-closed case) | RED (12b) |
| P1 | must-PASS non-canonical: whole-line comments mention `JOBS`, and the infra env reorders `TEST_GROUP` after another key | PASS |

Write rows 1 to 5 and P1 BEFORE changing the assertion (cq-write-failing-tests-before), watch (12b) go red against the current file and save that red output in `evidence.md` (the commit that follows carries guard and workflow together, so the red observation would otherwise leave no artifact). Raise `MIN_ASSERTIONS` (135 against a measured 147 today) by the rows added; the call-site `CASES` accounting is automatic for Python-emitted rows.

**Anchor.** The check compares the workflow to a stated property, not to a stored value. Restoring a pin therefore requires editing (12b) in the same diff, which a reviewer sees; the failure message states the revert procedure and points at the evidence (the `infra-validation` legs, #7432, the 2026-08-09 learning).

### Guard 2 — the soak probe `jobs1-stopgap-7432.sh`

**Property.** The probe exits 0 only when the workflow on main carries exactly one `JOBS` assignment token (the tests pin) AND the 12 OLDEST completed, non-cancelled monitor runs on `main` created at or after the sweeper-supplied `SOLEUR_FT_EARLIEST` (the directive's `earliest=`, set to the merge time) are all clean; it never exits 0 on a fetch it could not read, and once 12 such runs exist a later bad run cannot change the verdict (PASS is monotone, so the sweeper's closed-issue re-check cannot reopen #7432).

**Assembly.** The reads it depends on: the workflow text from main (contents API, whole-line comments stripped, the same token regex as Guard 1), the runs (`gh run list --workflow main-health-monitor.yml --branch main --limit 200 --created ">=$SOLEUR_FT_EARLIEST"`; a result that fills the limit is exit 3 because the oldest 12 may be missing), their jobs and `main-health-outcomes` check-run annotations, and, for a run reading `infra=failure` without a timeout annotation, the job log (`actions/jobs/<id>/logs`, `actions: read`) to list its `^RED  <path>` lines. A run is clean when it reads `infra=success`, or when its RED set is a subset of the allowlist `KNOWN_DETERMINISTIC_REDS` (today only `cloud-init-inngest-bootstrap.test.sh`, the tag-drift guard that is RED on main by design and reproduces in `infra-validation`); the probe prints which clean runs carried it. Exit codes follow the followthrough convention: 0 PASS; 1 FAIL when a counted run shows a ceiling kill (`Run infra suites ... has timed out`, revert trigger 2); 5 ACTION REQUIRED when a counted run has a RED outside the allowlist (the revert-trigger-1 judgement, whether it reproduces at the same sha in `infra-validation`, needs a human or agent; the probe names the run ids and suites); 2 NOT YET when the infra pin is still on main, fewer than 12 runs exist yet, or a counted run is still running; 3 CANNOT ESTABLISH on any fetch failure, a full run list, `SOLEUR_FT_EARLIEST` unset, or a non-cancelled run whose annotation is `ABSENT`; 78 when run under xtrace with `GH_TOKEN` set (the credential-refusal prologue of `ci-draft-light-soak-9728.sh`, which also lets the entry on line 30 of `scripts/lint-shell-trace-credential-refusal.baseline.txt` be deleted). A ceiling kill or a non-allowlisted RED among fewer than 12 runs already exits 1 or 5 (precedence 1 over 5 when both are present). Sweeper vocabulary (read in `scripts/sweep-followthroughs.sh`): 0 closes, 1 comments and reopens a closed issue, 2, 3 and 5 are the NOT YET, CANNOT ESTABLISH and ACTION REQUIRED headings. The annotation read needs `checks: read`, which the sweeper workflow does not grant (its explicit `permissions:` block lists `contents`, `issues`, `actions` only, and an unlisted scope is `none`): add `checks: read` to `.github/workflows/scheduled-followthrough-sweeper.yml` with a comment citing the #8450 precedent. State in the directive that cancelled runs are skipped (a job-ceiling cancel is not counted), that a manual `dry_run=true` dispatch on `main` would be counted (a valid sample), and that the realistic soak is 3.5 days or more because about 10% of runs have no verdict.

**Mutation matrix** (stub `gh` in `jobs1-stopgap-7432.test.sh`; the stub accepts exactly the modeled argv, exits 64 on anything else and logs the refusal, and the suite asserts that log empty, so a mutation of a selector in the probe's call lines cannot survive):

| # | Mutation | Expected |
|---|---|---|
| 1 | the infra step still carries a `JOBS` pin on main | exit 2, never 0 |
| 2 | fewer than 12 runs at or after the start; and bad runs created before the start (boundary: exactly at the start) | exit 2; the pre-start runs are ignored |
| 3 | 12 runs, one with a ceiling-kill annotation and a second bad run after a compliant first | exit 1 naming both run ids |
| 4 | a non-allowlisted RED and a ceiling kill both present; and a RED set that is allowlisted plus one other suite | exit 1 (precedence); exit 5 naming the suite |
| 5 | the annotation read returns an empty list (own dispatch: "0 checked" must not pass); a `gh` failure on the contents call; `SOLEUR_FT_EARLIEST` unset; a run list that fills the limit | exit 3, never 0 |
| 6 | 12 good runs followed by a later bad run | exit 0 (monotone) |
| 7 | a bad run on a `feat-*` branch (this PR's own dry-run dispatches) | ignored; the stub refuses a call without `--branch main` |
| 8 | run under xtrace with `GH_TOKEN` set | exit 78 |
| P1 | must-PASS non-canonical: 14 runs in shuffled order, 2 cancelled, 1 clean run whose only RED is the allowlisted suite, oldest 12 non-cancelled clean | exit 0 |
| X | cross-check: the real post-edit `.github/workflows/main-health-monitor.yml` served by the stub | the probe counts exactly 1 token, the same subject Guard 1 checks |

**Anchor.** The window start is the sweeper-supplied `earliest=` (the merge time written into the directive after merge), not a constant in the script and not the workflow file's last commit (the file changes about every four days, so a commit-time anchor would move the window and let an unrelated edit restart the soak or reopen a closed #7432). A first live sweep is the positive control that the annotation read works under the sweeper token; until then the probe fails safe at exit 3, so the postmerge step reads the first sweep comment on #7432.

## Rollback

`git revert` of the merge commit restores the infra-step pin, the original check (12), the original probe (which then reads two pins and exits 2 again) and the corrected comments. A revert forced by the revert trigger is a normal PR that restores the pin together with check (12b) flipped to assert it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "measure whether the JOBS=1 stopgap on both suite steps of .github/workflows/main-health-monitor.yml (the two `JOBS: 1` env lines, at about lines 342 and 369, with the explanatory comment block above the first) can be removed" | `## Measurement`, Phase 0, Phase 1 gate | mapped |
| 2 | "The outcome is either a PR that removes the stopgap with the measurement as evidence, or Item I recorded on #9217 as not fixed with the measured reason and a `Ruled by CTO agent` line" | Phase 1, Phase 4 (removal), Phase 5b (not fixed) | mapped |
| 3 | "take any technical ruling, including the soak threshold and what counts as enough merge-queue runs, to the CTO agent rather than the operator" | `## Decision`, `decision-challenges.md` (merge-queue note: `infra-validation` has no `merge_group` trigger) | mapped |
| 4 | "Measure first with real run data (pull the main-health-monitor run history yourself; do not ask the operator to fetch)" | `## Measurement` M1 to M4 | mapped |
| 5 | "run any instrument against a known-positive and a known-negative control before reading a count" | the controls table, `analyze.py` CONTROLS block | mapped |
| 6 | "Write the exact commands in the plan so the work phase can re-run them" | `## Measurement` command, Phase 1 steps 3 and 4 | mapped |
| 7 | "Keep raw run data under /var/tmp (not /tmp), and commit only a compact evidence file" | `ITEM_I_DIR`, Phase 4 step 1 | mapped |
| 8 | "Verify every one of those claims yourself (they were written 2026-08-11)" | `## Research Reconciliation` | mapped |
| 9 | "removal of both pins, and deleting check (12) from plugins/soleur/test/main-health-monitor-workflow.test.sh" | Phase 1 and Phase 2 | mapped, modified by CTO ruling: infra pin only, check (12) split (the ruled technical fork; recorded in `decision-challenges.md`) |
| 10 | "Done = Item I merged or recorded as not fixed with a reason on #9217, then soleur:postmerge for the PR if a PR is made" | Phase 4 steps 4 and 5, Phase 5b | mapped |
| 11 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | `decision-challenges.md` | mapped |
| 12 | "after any commit run `git log -1 --format='%an <%ae>'` and expect Jean Deruelle" | Phase 4 step 3 | mapped |
| 13 | "Do not emit DONE for this PR" | Phase 4 step 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow edit (infra pin and comment block) | "the two `JOBS: 1` env lines ... with the explanatory comment block above the first" | asked |
| Check (12) split | "deleting check (12) from plugins/soleur/test/main-health-monitor-workflow.test.sh" | asked, modified by the CTO ruling (a deletion would drop the guard against silent reintroduction) |
| Two dry-run dispatches | "a continue-on-error non-issue-filing probe job at -P 4 for CI-grade evidence" | asked in substance; the workflow's own `dry_run` replaces the new job (CTO Q2) |
| Probe rewrite and its test | "closes the tracker when they are gone" | inferred — justification: with one pin kept the old probe can never exit 0, so #7432 and, through `suite-runner-flake-7376.sh`, #7376 would never close; CTO Q4 requires a followthrough directive |
| `checks: read` in the sweeper workflow and the baseline-line removal | "closes the tracker when they are gone" | inferred — justification: the probe reads annotations that a token without `checks` cannot, so without the permission #7432 never closes; the baseline line exists because the old probe holds `GH_TOKEN` with no xtrace refusal and a rewrite under `--changed` forces the remediation |
| Registration line in `scripts/test-all.sh` | — | inferred — justification: an unregistered suite is an orphan (`lint-orphan-test-suites.sh`) and the probe's exit contract would be a comment nothing drives |
| Comment corrections in `infra-validation.yml`, ADR-252 and the series-state header of `grep-q-pipe-guard.test.sh` | "Verify every one of those claims yourself" | inferred — justification: three files state "main-health-monitor keeps JOBS:1" or list Item I as open, and become false after this PR (the `run-registered-suites.sh` clause is left, Phase 2.4) |
| `measure/` instruments | "Write the exact commands in the plan so the work phase can re-run them" | asked |
| `evidence.md`, `decision-challenges.md` | "commit only a compact evidence file"; "Persist every decision as a row" | asked |

### Split Assessment

- Subsystems touched: 5 (`.github`, `.claude`, `plugins`, `scripts`, `knowledge-base`)
- Planned files: 15 (9 edited, 6 created) | Estimated changed lines: about 600 (the probe suite is the bulk; sibling followthrough suites run 480 to 821 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The workflow edit, the guard that asserts it and the probe that closes its tracker are one atomic unit (splitting would red check (12) or leave a probe that can never pass); `.claude/hooks` and ADR-252 are comment-only corrections of statements this edit falsifies.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled (2026-10-16, no AskUserQuestion) on the evidence bar, the deadlock premise, the option choice (D), the work-phase gate, the revert trigger and check (12). No ADR needed. No product, marketing, legal, finance, sales, support or operations domain is touched (an internal CI monitor); no UI surface, so no wireframe and no copy review.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `measure/run-all.sh` ran in the work phase and printed `CONTROLS OK` before any count was read; its M1 to M4 figures are in `evidence.md` with the command beside each.
- [x] Two `dry_run=true` dispatches of the branch workflow both show `-P 4`, `infra=success` (or only the known tag-drift RED), `infra_elapsed_s` at most 2400 (a third dispatch exists in `evidence.md` if one landed in 2400 to 3000 s), no ceiling-timeout annotation, no `[KILLED]`, no `UNACCOUNTED`; run ids and values are in `evidence.md`.
- [x] `grep -nE '^\s+JOBS:' .github/workflows/main-health-monitor.yml` returns exactly one line, inside the tests step env block (verified by the (12a)/(12b) rows, `.github/workflows/main-health-monitor.yml:<tests step env>`).
- [x] Check (12) is split into (12a) and (12b) over `check_jobs_pin(text)`; Guard 1 rows 1 to 5 and P1 exist as in-Python assertion pairs in `plugins/soleur/test/main-health-monitor-workflow.test.sh`, each RED row reds on its mutated copy and P1 passes; the suite's assertion count rose by exactly the number of rows added.
- [x] `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` passes on the final tree.
- [x] `scripts/followthroughs/jobs1-stopgap-7432.test.sh` covers Guard 2 rows 1 to 6 and P1; it is registered in `scripts/test-all.sh` with one `run_suite` line and `scripts/lint-orphan-test-suites.sh` passes.
- [x] `python3 scripts/lint-guard-contract.py` passes on this plan file; `python3 scripts/lint-shell-trace-credential-refusal.py` is green with the probe's baseline line deleted; `plugins/soleur/test/fixture-relative-assert.test.sh` and the `PJ_TRIPLES` recompute are unchanged by the new suite; `.github/workflows/scheduled-followthrough-sweeper.yml` carries `checks: read`.
- [x] The workflow comment block states the infra step runs at the default width, cites #7432 and the legs, and contains no literal `JOBS: 1` token.
- [x] `infra-validation.yml` and ADR-252 no longer say the monitor keeps `JOBS: 1` for the infra step, and the `grep-q-pipe-guard.test.sh` header no longer lists Item I as open; `git diff origin/main...HEAD --stat` shows no `apps/` path.
- [x] `decision-challenges.md` carries one row per ruling with a `Ruled by CTO agent, 2026-10-16` line.
- [x] Every commit on the branch reads `Jean Deruelle <...>` under `git log --format='%an <%ae>'`.
- [ ] PR body uses `Ref #7432` / `Ref #9217` and carries the figures, the revert trigger and the CTO lines.

### Post-merge (operator-free)

- [ ] `soleur:postmerge` ran for the PR (CI on main, deploy arm, Sentry monitors), and the first sweep comment on #7432 after the directive edit is NOT YET (exit 2), not CANNOT ESTABLISH (exit 3): that proves the annotation read works under the sweeper token with `checks: read`.
- [ ] #7432's directive line points at the rewritten probe with `earliest=` set to the merge time (the probe's soak window start) and carries the revert trigger, the fire-rate caveat and the #7376 assumption; #7432 stays open.
- [ ] #9217 carries the Item I merge comment with the figures, the CTO lines and the revert-trigger window.
- [ ] Within the soak window: if revert trigger 1 or 2 fires, the infra pin is restored in a PR that also edits check (12b), and #9217 is amended.

## Test Scenarios

- Given the final workflow, when `check_jobs_pin` runs against each of Guard 1's five mutated in-memory copies, then each reds (unit, Python inside the shell suite).
- Given a copy whose comments mention `JOBS` and whose infra env reorders keys, when (12) runs, then it passes (unit).
- Given stub `gh` fixtures for Guard 2 rows 1 to 6 and P1, when the probe runs, then exit codes are as listed and never 0 on an unreadable fetch (unit, shell with stub `gh`).
- Given the branch workflow, when dispatched with `dry_run=true`, then no issue is filed or closed and no Sentry check-in is sent (integration; verify with `gh issue list --label ci/main-broken` before and after, and the `!inputs.dry_run` conditions).
- Given run 38897624648 (positive control) and a `success success` run (negative control), when `analyze.py` runs, then `CONTROLS OK` prints (unit, Python).
- Regression: the Aug 2026 regression (infra runner back at `-P 4` unnoticed, run 31367748528) is why check (12) exists; pin gone is now the intended state, and the dispatch gate plus the soak replace that guard's old premise.

## Dependencies & Risks

- **Risk: a parallel-only flake files spurious P1s.** Bounded by the dispatch gate (2 runs), the revert trigger (12 runs, early revert after 3) and the fact that the same suites already run at `-P 4` in CI, 4 legs per push. A zero in 2 dispatches does not bound the rate; the soak does the bounding. Read the 13.6% figure correctly: it counts isolated suite-events over push runs and includes one-commit regressions, so it is an upper bound on the parallel-only rate. Taken literally it would put the expected spurious comments in 12 monitor runs at about 1.6 and the chance of two or more near 50%, which would fire revert trigger 1 on the plan's own bound; the trigger counts only a RED that does NOT reproduce at the same sha in `infra-validation`, and a regression that does reproduce is a real finding the monitor exists to report. If the dispatches or the first runs show the rate is near the bound, take the revert.
- **Risk: the monitor's runner is not a fresh runner.** The legs start fresh; the monitor's infra step starts after the 110-minute tests step (killed in 129 of 300 runs), which can leave orphaned children, disk and docker state. The legs therefore do not prove the same environment; the dispatches (which run the same sequence) are what test it, with n=2, and the first scheduled runs after merge are the continuing test.
- **Risk: the dispatch cost.** Each dry run is about 2.5 hours of a hosted runner; two are serial. Accepted by the CTO bar; no production mutation, no tracker writes.
- **Risk: the tests step keeps timing out** (129 of 300, #9410). After this PR the monitor still ends red on that step until #9410 lands; the probe reads the infra field only, so the soak is not masked by it. `#9457` (sentinel) keeps receiving "terminated before it could report" comments from the tests step; revert trigger 1 counts only comments naming a suite RED.
- **Risk: ceiling over-provisioning.** The infra ceiling (60 min) and its Sentry coupling (`max_runtime_minutes`, test G2) are unchanged; faster runs are safe. Re-deriving them is out of scope.
- **Dependency:** `gh` auth with Actions read; the branch must be pushed for the dispatch. The sweeper workflow gains `checks: read` for the annotation read; until the first live sweep proves it the probe fails safe at exit 3 and does not close #7432.
- **Limitation kept:** the stale clause in `apps/web-platform/infra/run-registered-suites.sh` (Phase 2.4) and a manual `dry_run=true` dispatch on `main` being counted by the probe (it would be a valid infra sample).

## Non-Goals

- Changing the tests-step timeout cause (#9410 owns sharding the tests step; acknowledged, not folded).
- `JOBS: 2` or any other width (fallback only after a failed gate, as its own measured change).
- Editing the issue-filing logic or the ceilings.
- The Wave A3 carriers and the #9639 / #9638 triage (later series items).

## Sharp Edges

- `analyze.py` pairs monitor and leg runs by `headSha`; a re-run later than 90 days after a run loses its logs, so keep `ITEM_I_DIR` data for the PR's lifetime.
- The probe and `analyze.py` read `infra=` from the annotation titled `main-health-outcomes` only; the run and job `conclusion` is `success` for nearly every run (`continue-on-error: true`) and says nothing.
- The pin-removal comment must not contain the literal `JOBS: 1`; the unrewritten probe of the same file set (and any `git grep 'JOBS: 1'`) would count it.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one carries `none` with the sensitive-path scope-out bullet.
