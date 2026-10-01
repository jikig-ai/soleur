---
title: "fix: main-health-monitor reports a step-budget exhaustion as 'main branch tests failing'"
type: fix
date: 2026-10-01
slug: fix-main-health-monitor-step-budgets-and-failure-classifier
branch: feat-one-shot-8112-main-branch-tests-failing
issue: 8112
closes: 8112
lane: cross-domain
---

<!-- markdownlint-disable MD038 -->

# fix: main-health-monitor reports a step-budget exhaustion as "main branch tests failing"

## Enhancement Summary

**Deepened on:** 2026-10-02
**Agents used:** architecture-strategist, security-sentinel, observability-coverage-reviewer,
best-practices-researcher (haiku, docs check); plan-review panel before it (DHH, Kieran,
code-simplicity per mechanism, CTO devex lens). Halts run and passed: User-Brand Impact (4.6),
Observability (4.7), PAT-shaped variables (4.8, none), Encryption Posture (4.10, no store),
Guard Contract (4.11, `lint-guard-contract.py` green, 2 entries); UI-wireframe (4.9) and
downtime/cutover (4.55) not triggered.

### Key improvements

1. Verdict simplified to the runner's own breakdown (plan review), then hardened by the architecture
   review: display greps are separate so control `[FAIL]` lines cannot crowd out a `RED`, and the
   `ERROR: parent process gone` watchdog line is shown as measured evidence of a kill.
2. Measurement made sound: "uncensored" no longer means `tests=success` (the Sentry parity row would
   be red mid-flight), the dry run also measures the infra step, and the claim that a branch run
   selects different suites than main was corrected (only the nested infra gate differs).
3. Observability: layer citations added to every failure mode, the discoverability probe now checks the
   changed property offline (`grep` for `tests_elapsed_s`), and the `$GITHUB_OUTPUT` elapsed value
   reaches the annotation through `env:` behind a numeric guard.
4. Sentry slack `+25` is now backed by the monitor's own measured queue and dispatch-lag population.

### New considerations discovered

- An infra step still red keeps the Sentry check-in at `error` on every run; stated as a residual.
- A dry run displacing a scheduled pending run reads as a Sentry missed check-in: the dispatch window
  is boundary + 80 min to boundary + 3 h with nothing in flight or queued.
- The docs-check agent reported three claims as "contradicted"; live evidence overrides it: step-timeout
  `outcome=failure` (run 34726833667 log), unauthenticated read of check-run annotations (fetched live
  for run 36903587088), and pending-run replacement (stated in the workflow's own header, measured
  2026-08-06). The `--ref` dispatch of an existing workflow is supported by GitHub for a file already on
  the default branch.
- `scripts/test-all-killed-classification.test.sh` (A1c) reads the monitor's `[KILLED]` regex and the
  monitor test's duration row in `scripts/suite-durations.tsv` are readers to re-check in Phase 4.

## Overview

Issue #8112 ("CI: main branch tests failing") is the standing tracker the main-health-monitor
workflow (`.github/workflows/main-health-monitor.yml`) filed on 2026-09-13 and has commented on every
six hours since (76+ "still not passing" comments, the latest 2026-10-01T19:02Z). Verified against the
live run logs, **main's tests are not failing**. What is failing is the monitor itself, in two stacked
ways:

1. **Misreport (classifier defect).** The filer's failure marker includes a bare `^\[FAIL\]` grep.
   Seven `[FAIL]` lines in the quoted summary are self-labelled EXPECTED positive controls printed by
   test suites that exercise their own `fail()` helper. They select the "tests failing" arm and title
   the tracker accordingly, while the same capture's runner breakdown says `0 failed`.
2. **Real failing signal (budget exhaustion).** The `Run test suite` step is killed by its own
   `timeout-minutes: 40` ceiling on every run, and `Run infra suites` by its `timeout-minutes: 20`
   ceiling. The ceilings were derived from run durations that the previous ceiling had already
   censored, and the suite set has grown since (414 suites; 159 registered infra suites vs 117 on
   2026-09-13). A step the runner kills reports `outcome=failure`, so `tests=failure` is a true
   statement that carries no suite verdict.

The fix repairs the classifier so the tracker names only what the job measured, re-derives the tests
ceiling from an uncensored measurement, and re-aligns the Sentry cron-monitor envelope that is coupled
to the job ceiling (and is already stale: its comments say 65, the workflow says 75). This is an
explicit **stopgap** for the budget half: the structural fix (sharding the monitor) is deferred to #9410
with numeric triggers.

Out of scope, owned by another session: the git-data suites and bounded-apt code (draft PR #9383 for
#9379). This plan touches none of those files.

## Research Reconciliation — Spec vs. Codebase

The brief hypothesised three candidate causes. Reconciled against live evidence:

| Brief hypothesis | Reality (evidence) | Plan response |
|---|---|---|
| (a) monitor classifier greps `[FAIL]` and matches expected control lines | **True, but secondary.** `main-health-monitor.yml` greps `^RED \|^UNACCOUNTED \|^\[FAIL\]` and sets `HAS_FAIL_MARKER` from any hit; the 7 quoted lines are controls and the capture's breakdown reads `413 passed, 0 failed`. | Phase 2: the runner's breakdown, not `[FAIL]`, is the verdict. |
| (b) stale/false report, underlying run is green now | **False.** Every monitor run since 2026-09-17 ends `tests=failure` (the step ran 2411-2413 s, i.e. the 40-min ceiling, in 60 of 60 listed runs); the latest run 36903587088 (2026-10-01T18:00Z) is `tests=failure infra=failure`. The run *conclusion* is `success` only because both suite steps carry `continue-on-error: true`. | Not stale; fix the cause (Phase 3). |
| (c) genuine suite failure | **False for the tests step.** Issue run 34726833667: step started 00:01:24, `##[error]The action 'Run test suite' has timed out after 40 minutes` at 00:41:37, zero `RED` lines. The `413/414 suites passed` tail in the issue body is **not in the step's live log** (`gh run view --log` has zero hits for `413 passed`): it is the epilogue of an orphaned `test-all.sh` that outlived the killed step and appended through `tee -a` before the filer read the capture at 00:55:15. | Phase 3 re-derives the ceiling; Phase 2 stops the mislabel. |
| (new) a real-shaped `[FAIL]` can also appear on a timeout | On the latest run the step ceiling killed the parent shell and the `#8993` parent-death watchdog in `scripts/test-all.sh` killed the in-flight suite, which renders as `[FAIL] scripts/test-affected-kb-consumers (198336ms)`; the runner then died, so no breakdown line was ever printed. | Phase 2: a `[FAIL]` line is display-only; only a printed breakdown with at least one failed suite counts. |
| (new) the ceiling is the failure | At the 40-min kill on the latest run 256 of 414 suites had finished (2209 s of suite time). Infra step: pinned at its 15-min ceiling (912 s) from 2026-09-11 and at its 20-min ceiling (1208-1213 s) from 2026-09-25, before the #9379 apt stall began (2026-10-01 ~15:00Z). | Phase 3. |
| (new) the Sentry envelope is coupled to the job ceiling | `apps/web-platform/infra/sentry/cron-monitors.tf` `sentry_cron_monitor.main_health_monitor`: `max_runtime_minutes = 65`, `checkin_margin_minutes = 90` (= 65 + 25) while the workflow's job ceiling is 75. Nothing pins the relation. | Phase 3 re-aligns it; Phase 1 adds a parity guard. |

## Research Insights

**Premise validation (Phase 0.6).** Cited by reference: #8112 (`OPEN`, labels `ci/main-broken`
`priority/p1-high` `type/bug`, `closedByPullRequestsReferences: []`, so not already resolved), #9379
and draft PR #9383 (OPEN draft; its file list is confined to `apps/web-platform/infra/git-data-*`,
`apt-bounded*` and its own plan/spec files; no overlap), run ids 34726833667 and 36903587088 (both read
in full via `gh run view -R jikig-ai/soleur --log`). No open PR touches `main-health-monitor.yml`, its
test, or `sentry/cron-monitors.tf`. No ADR covers this monitor's classifier or ceilings (ADR-166 states
the rule this plan applies: a CI message may only name a cause the job measured).

**Property List (Phase 0.6b).**

- P1. A run whose capture holds only expected-control `[FAIL]` lines and whose runner breakdown reports
  zero failed suites is not titled "main branch tests failing".
- P2. A run whose step was killed before the runner printed a breakdown is not titled "tests failing",
  even when a suite-termination artefact rendered a `[FAIL]` line. Both shapes occur: a breakdown with
  `0 failed` written by an orphaned runner after the kill (run 34726833667), and no breakdown at all
  (run 36903587088). Neither fixture may be "corrected" into the other.
- P2b. An infra step killed at its ceiling keeps the existing "terminated" arm (the capture ends with
  `[KILLED] ...run-registered-suites.sh (exit=143, ...)` and a `1 killed` breakdown, as on run
  36903587088); only the tests step, whose capture has no such line, lands on "did not complete".
- P3. A genuinely failing run (a `RED`/`UNACCOUNTED` line, or a printed breakdown with at least one
  failed suite) still titles "tests failing"; the classifier must not reject everything.
- P4. The tests step completes inside its ceiling on a healthy main, the ceiling being derived from an
  uncensored measurement, and each run records its own elapsed time so the next derivation is cheap.
- P5. The Sentry cron-monitor envelope (`max_runtime_minutes`, `checkin_margin_minutes`) is consistent
  with the workflow's job ceiling, and a mechanical check keeps it so.
- P6. The public issue body shows the capture tail once and carries no `SOLEUR| ` diagnostic line.

**Cut List (Phase 0.6b; the first three were cut by the plan-review panel).**

| Mechanism considered | Property it would buy | Already covered by / why cut |
|---|---|---|
| Shape-anchor `[FAIL]` to `(<N>ms)` and require it to precede the breakdown | P1, P2 | The breakdown's failed count is the runner's own verdict and already separates the controls (0 failed) from a real failure; the anchor and the ordering comparison were a second gate on the same signal. |
| Rewrite the arm-4 lede | P2 | The existing arm-4 lede already states only the measured outcome (ADR-166 check (8e) covers it); only the arm's `ACTIONS` is wrong. |
| Second serialised dry run, plus a duplicate-member / skipped-row Guard 2 matrix | P4, P5 | One uncensored run plus the 1.5x margin and the independent cross-checks below; Guard 2 trimmed to the relations that can drift. |
| Exit-status sidecar file written by the step wrapper, read by the filer | P2 | The breakdown line is already the runner's own once-only completion marker. |
| `timeout --kill-after` wrapper inside the step to render rc 124 | P2/P4 | Duplicates GitHub's own step ceiling and adds a second budget to keep in step. |
| New tracker arm "timed out" | P2 | Arm 4 ("did not complete") is the honest arm already. |
| Shard the monitor into parallel legs reusing the ADR-240 shard manifest | P4 | Real structural fix, but a rewrite of an ~800-line workflow and its ~1000-line test; deferred to #9410. |
| Touching git-data suites / bounded apt | n/a | Owned by PR #9383. Out of scope by instruction. |

**Key evidence (commands that produced the numbers).**

- Step durations per run: `gh run view <id> --json jobs --jq` over `Run test suite` / `Run infra suites`
  (`startedAt`/`completedAt`), 60 consecutive runs 2026-09-17 to 2026-10-01: tests 2411-2413 s; infra
  747-914 s until 09-25 (15-min ceiling) then 1208-1213 s (20-min ceiling).
- Suite progress at kill: `grep -E '\[ok\] .* \([0-9]+ms\)$'` over the tests-step region of run
  36903587088 gives 256 suites, 2209 s of suite time; the last printed suite header is
  `test/pre-merge-rebase` (the bun group), so the webplat group and the 345 s fixture runner had not
  started. Independent bounds for the derivation cross-check: the orphaned runner of run 34726833667
  had finished by 00:55:15 (at most ~54 min after start, sharing the runner with the infra step for 14
  min), and the linear extrapolation 2209 s x 414/256 is about 60 min.
- Infra capture on 36903587088 last printed `PASS ...git-data-root-key.test.sh` at 18:56:26, then
  nothing until SIGTERM at 19:02:38 (20:00 after step start).
- Step-timeout semantics: a step `timeout-minutes` kill reports `outcome=failure` here (live: `timed
  out after 40 minutes` alongside `tests=failure`); only a JOB-level timeout is `cancelled`. Both are
  handled by the filer's `!= 'success'` condition.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-08-09-the-monitor-reported-success-and-i-read-the-field-that-cannot-say-otherwise.md`
  (read `steps.<id>.outcome`, never `conclusion`).
- `knowledge-base/project/learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`
  (a cancel is reported at the running step, not the one that consumed the budget; read per-step durations).
- `knowledge-base/engineering/architecture/decisions/ADR-166-a-ci-message-may-only-name-a-cause-the-job-measured.md`
  (governs the arm-4 actions wording).
- `knowledge-base/project/learnings/2026-09-22-one-monitor-four-red-gates-each-named-its-own-remedy.md`
  (a monitor change is a registry update across several ledgers; the Sentry TF block is one).

## Problem Statement / Motivation

A P1 `ci/main-broken` tracker has been open for 19 days and carries a title and body that point at
tests that pass, so a reader hunts for a failing suite that does not exist while the actual defect (a
monitor that cannot finish inside its own ceilings) goes unnamed. A monitor that is permanently red
also trains everyone to ignore it, which is the condition under which a real main break goes
unnoticed. The reporting must tell the truth and the monitor must be able to finish.

## Proposed Solution

1. **Classifier (P1-P3, P6)** in the filer step's excerpt loop:
   - Demote `[FAIL]` from verdict marker to display line. `HAS_FAIL_MARKER=1` iff the capture holds a
     `^RED |^UNACCOUNTED ` line (the infra runner's own verdict) **or** the runner's breakdown reports
     at least one failed suite, matched by
     `^=== [0-9]+ suites: [0-9]+ passed, [1-9][0-9]* failed, [0-9]+ killed \(` (shape taken from the
     `=== $suites suites: ...` echo in `scripts/test-all.sh`; the 0-failed breakdown and the
     killed-only breakdown do not match it). `^\[FAIL\]` lines keep entering `SUMMARY` through the
     existing display capture so the reader still sees them, under an explicit label
     (`--- unconfirmed [FAIL]-shaped lines (no failing breakdown) ---`) whenever the verdict regex did
     not match, so an arm-4 body never shows a bare `[FAIL]` under a "never reported a result" lede.
     Implementation shape: the display capture uses separate `-m 20` greps, `^RED |^UNACCOUNTED ` first and
     `^\[FAIL\]` second (a single 20-line cap over all three alternates lets early control `[FAIL]`
     lines crowd out a later `RED`), and two verdict greps (`^RED |^UNACCOUNTED `; the breakdown regex)
     feed `HAS_FAIL_MARKER`. When the capture holds the runner's own
     `ERROR: parent process gone` watchdog line (`scripts/test-all.sh`, #8993) the body shows it: it is
     measured evidence that the step was killed under the runner, not an inference from a missing
     breakdown.
   - Delete the second, unfiltered `SUMMARY="${SUMMARY}$(tail -30 "$file")"` append. It re-adds the raw
     last 30 lines after the `grep -v '^SOLEUR| ' | tail -30` append, which duplicates the tail in the
     body (visible in #8112's own body) and defeats the public-body filter; the behavioural harness
     evaluates only the filtered expression, so nothing guards the raw one today. Also delete the
     `--- (tail) ---` header that follows the killed hits (it labelled that raw tail and would label
     nothing); no `--- (tail) ---` label may precede an empty block.
   - Give arm 4 its own `ACTIONS` (today it inherits "identify the commit and revert it"): (1) this run
     produced no suite verdict, so main's health is unverified, not known-broken; (2) read the run log's
     step list for the step that stopped and compare its elapsed time with its ceiling in the
     workflow, if the printed elapsed time is close to the printed ceiling; (3) inspect any `[FAIL]`-shaped lines listed above, because a genuine failure printed before the step
     ended would be shown but not confirmed by this run; do not revert on the strength of this issue
     alone. Arm 4 also catches non-budget endings (a runner crash, an early
     abort), so action (2) is conditional on the measured figures, not a stated cause (ADR-166). The
     lede is unchanged.
   - Record each suite step's elapsed seconds and print it in the existing `SOLEUR_MAIN_HEALTH`
     annotation (`tests_elapsed_s=<n>`; absent when the step ended before the runner returned, which
     marks that sample as censored). Every later re-derivation then reads uncensored figures from
     ordinary runs. Security hardening (review): the value reaches the annotation and the filer through
     `env:` and is emitted only when it matches `^[0-9]+$`, never inlined raw via `${{ }}` into an
     `echo "::notice ..."` (`$GITHUB_OUTPUT` is inherited by every suite child, so a non-numeric value
     could carry a workflow command). The filer's `Step outcomes` line also prints the two figures and
     the step ceilings, so the arm-4 body shows the measured elapsed time next to the ceiling.
2. **Budget (P4).** Re-derive `tests_step` and `job` with the file's own rule from an uncensored
   dry-run measurement and update the derivation comment; `infra_step` only when it can be measured
   undisturbed by #9379 (see Technical Considerations).
3. **Sentry envelope (P5).** Set `max_runtime_minutes` to the job ceiling and `checkin_margin_minutes`
   to the job ceiling plus 25 in `apps/web-platform/infra/sentry/cron-monitors.tf`, correct the stale
   "65" comments, and add a parity assertion to the workflow's static test. Applied on merge by the
   existing `apply-sentry-infra.yml`.

## Technical Considerations

- **Measurement without censoring.** An uncensored tests-step duration needs a ceiling above the need.
  The workflow's `dry_run` input is "measure only" (no tracker, no heartbeat; the filer, closer and
  Sentry steps all carry `!inputs.dry_run`). Dispatch the **branch's** workflow with `--ref` after a
  measurement commit raises the ceilings. **Uncensored means** the step ended before its raised ceiling and the runner printed its
  `=== N suites:` breakdown; it does **not** mean `tests=success`. The measurement commit raises the
  job ceiling while the Terraform commit is deliberately withheld, so the Guard 2 parity row inside
  `TEST_GROUP=all` (`plugins/soleur/test/*.test.sh` is in the suite globs) is expected RED on that run,
  and main may carry other reds. Take the run's `tests_elapsed_s` as `T_max`; cross-check it against the
  two independent bounds above (about 54 and 60 min). If it lands below ~40 min or the step was killed,
  do not derive from it: investigate or raise the ceiling and re-run. Suite selection on a branch dry run equals
  main's: under `CI` the diff gates return "run" except for pull_request-gated call sites
  (`scripts/test-all.sh`, ADR-262), and a `workflow_dispatch` is not a pull_request event. The only
  branch-vs-main difference that matters is the nested infra runner (gate: `apps/web-platform/infra/`
  or `apply-web-platform-infra.yml` in the three-dot diff `origin/main...HEAD`), which the commit
  ordering below avoids; confirm the branch carries no other infra change and is not behind main.
- **Redaction ordering.** Any new display block (the unconfirmed-`[FAIL]` label, the elapsed line) must be
  appended to `SUMMARY` before the `REDACTED=$(...)` pass, and the new verdict greps feed only
  `HAS_FAIL_MARKER`; nothing is echoed into the body after redaction (security review: no unredacted
  path exists today, and this keeps it so).
- **Concurrency.** The `main-health-monitor` group keeps one running and one pending run, and a newer
  pending run replaces an older pending one. The Inngest dispatcher fires at 00/06/12/18Z UTC. Dispatch
  the dry run only when no run is in flight or queued
  (`gh run list --workflow main-health-monitor.yml --status in_progress` and `--status queued`) and
  inside the window from boundary + 80 min (the scheduled run, which still has the old 75-min ceiling,
  has finished) to boundary + 3 h (so the ~1-2 h dry run finishes before the next dispatch could queue
  behind it). A dry run sends no heartbeat, so a scheduled run it displaced from the pending slot
  would surface as a Sentry missed check-in; the in-flight/queued check is therefore a hard
  precondition, not a courtesy. Scheduled runs on main keep their old ceilings, so they stay red until
  this PR merges.
- **The nested-infra trap.** `scripts/test-all.sh` runs the nested infra runner inside the tests step
  whenever the branch diff touches `apps/web-platform/infra/`, which inflates the tests figure (the
  workflow header documents it). The Terraform edit lives under that path, so it lands in a **later
  commit** than the one the dry run is dispatched from; a dispatch resolves the ref's sha when it is
  created, so do not push the TF commit until the run exists.
- **Infra step.** If PR #9383 has merged by work start, rebase and measure the infra step in the same
  dry run and derive its ceiling; if not, leave it untouched and say so in the PR. Do not guess a number.
- **Job ceiling arithmetic (existing test row (6)).** `job >= tests_step + infra_step + 15` and
  `job < 360`; `tests_step = max(30, roundup5(1.5 * T_max))`. The 1.5x is the file's stated slack
  assumption, not a variance estimate.
- **Sentry envelope trade-off.** The monitor sends one terminal check-in, so `max_runtime_minutes` is
  decorative (the file says so for sibling monitors) and the margin must cover the whole run. The
  `+25` slack is kept from the old derivation and now checked against the monitor's own population
  (measured at plan time over the last 30 runs: job queue delay `started_at - created_at` from
  `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs` has median 3 s, p90 40 s, max 342 s; dispatch
  lag after the 6-hour slot has p90 1 min, max 3 min), so `+25` covers the observed worst case with room;
  it does not cover multi-hour dispatcher deferral, which the Sentry scheduler watchdog owns. Accepted consequence: a dropped
  dispatch is detected about `job + 25` minutes after its slot instead of 90. An `in_progress` check-in
  at job start would decouple margin from run length; recorded as a candidate in #9410, not done here.
- **Every workflow that can apply the TF edit.** `apply-sentry-infra.yml` (push on
  `apps/web-platform/infra/sentry/**`; intended). `apply-web-platform-infra.yml` also fires on any
  `apps/web-platform/infra/**` push (the `sentry/` subtree is not excluded) but applies a different
  root, so its plan should be empty for this change; confirm that after merge. `scheduled-terraform-drift.yml`
  is read-only.
- **No change** to `run-registered-suites.sh`, `test-all.sh`, the infra suites, the Inngest dispatcher,
  or the Sentry alert routing.

## Implementation Phases

### Phase 1 — RED first (tests before the workflow edit)

Edit `plugins/soleur/test/main-health-monitor-workflow.test.sh` (cq-write-failing-tests-before):

1. Keep assertion (8) (the display `hits` grep still carries all three alternates) and add (8g): the
   verdict greps carry `^RED ` / `^UNACCOUNTED ` and the breakdown regex with `[1-9][0-9]* failed`, and
   the breakdown shape is derived from the `=== $suites suites:` echo in `scripts/test-all.sh` so a
   runner-side rename reds the suite. The behavioural rows below are the real test that `[FAIL]` is not a
   verdict input.
2. Add fixtures beside `fx-killed.txt`:
   - `fx-controls-zero-failed.txt`: the seven control lines from #8112 plus a tail ending in
     `=== 414 suites: 413 passed, 0 failed, 0 killed (unresolved — coverage not obtained), 1 skipped (declined — not relevant to this diff) ===`.
     Expect arm 4 (title `CI: main-branch health check did not complete`), never `tests failing`.
   - `fx-fail-no-breakdown.txt`: the live shape of run 36903587088, a `[FAIL] scripts/test-affected-kb-consumers (198336ms) log=/var/tmp/x.log`
     line, the runner's `ERROR: parent process gone` watchdog line and no breakdown. Expect arm 4, with
     the watchdog line and the unconfirmed-`[FAIL]` label in the body.
   - `fx-fail-corroborated.txt`: a `[FAIL]` line whose label contains spaces
     (`apps/web-platform [unit] (1234ms) log=...`) plus `=== 414 suites: 412 passed, 2 failed, 0 killed (...`.
     Expect arm 2 (`CI: main branch tests failing`): the must-pass, non-canonical input.
   - `fx-red-only.txt`: infra-style `RED  apps/web-platform/infra/x.test.sh`, no breakdown. Expect arm 2.
   - `fx-infra-killed.txt`: the infra tail of run 36903587088 (`[KILLED] apps/web-platform/infra/run-registered-suites.sh (exit=143, signal-shaped 128+15 = SIGTERM, 1207161ms) ...`
     and `=== 1 suites: 0 passed, 0 failed, 1 killed (...`). Expect arm 3 ("terminated"), not arm 4.
   - A two-capture case: tests capture controls-only with `0 failed` (compliant first member) and an
     infra capture with a `RED` line. Expect arm 2. This needs a harness extension: `run_filer`
     currently writes an empty `infra-output.txt` and hardcodes `INFRA_OUTCOME=success` (the loop skips
     success outcomes), so it gains a second-capture argument and an `INFRA_OUTCOME` parameter, which
     `fx-infra-killed.txt` uses too.
3. Add the leak assertion: a capture whose last 30 lines include `SOLEUR| ` lines yields a body with
   zero lines matching `^SOLEUR| ` (anchored: the body legitimately quotes the `grep 'SOLEUR| '`
   command that points at the run log) and the tail block exactly once, on both the failing and the
   killed arm, with no empty `--- (tail) ---` label.
4. Add the arm-4 actions assertion: its `ACTIONS` do not instruct a revert and say the run produced no
   suite verdict; the existing (8e) causal-phrase check keeps covering the lede.
5. Add the annotation assertion: the `main-health-outcomes` notice carries `tests_elapsed_s` and
   `infra_elapsed_s`.
6. Add the Sentry parity guard (Guard 2): strip `#` comment lines from `cron-monitors.tf` first (its
   comments quote `max_runtime_minutes`, `checkin_margin_minutes = 90` and `timeout-minutes: 65`), find
   the resource block whose `name = "main-health-monitor"` (other monitors also set
   `max_runtime_minutes`, so scope the match to that one block) and assert exactly one such block;
   parse the workflow's job-level `timeout-minutes`; assert `max_runtime_minutes == job`,
   `checkin_margin_minutes >= job + 25` and `< 360`. A missing block or an unparsable number is a RED,
   not a skip. Add an `MHM_SENTRY_TF` override beside the existing `MHM_WORKFLOW` override so the
   sandbox mutation battery can mutate the TF copy as well.
7. Raise the anti-vacuity floor (`floor 63`, a lower bound, not an equality) to the new dispatched
   count and state the number in the PR; every behavioural row runs in both the `-e` and
   `-eo pipefail` arms, so count rows x 2.

Run the suite: it must go RED on the new rows before Phase 2 (record the failing rows).

### Phase 2 — Classifier, tail and annotation edit

Edit the filer step and the two suite-step wrappers in `.github/workflows/main-health-monitor.yml` per
Proposed Solution §1. Keep `rc=${PIPESTATUS[0]}` as the first statement after each pipeline (test row
(7)); write the elapsed seconds to `$GITHUB_OUTPUT` after it. Update the header's defect list with a
fifth entry (a bare `[FAIL]` grep titled a step-budget exhaustion as failing tests). Re-run the suite:
Phase 1 rows now GREEN.

### Phase 3 — Budgets and Sentry envelope

1. **Measurement commit** (workflow only, on top of Phase 2): raise `Run test suite` to 90 and `Run infra suites` to 45 and the job
   to `90 + 45 + 15` (still < 360). Push and dispatch once:
   `gh workflow run main-health-monitor.yml --ref feat-one-shot-8112-main-branch-tests-failing -f dry_run=true`.
   Arm a `Monitor` until-loop on `gh run view <id> --json status,conclusion`
   (hr-dispatch-async-must-arm-watch, hr-monitor-not-run-in-background-for-polling).
2. **Read the result from the right field.** `steps[].conclusion` is pinned to `success` by
   `continue-on-error`; the verdict is the `SOLEUR_MAIN_HEALTH tests=<outcome> infra=<outcome>
   tests_elapsed_s=<n>` annotation (`gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations`).
   Confirm the runner printed its breakdown (`gh run view <id> --log | grep -E '=== [0-9]+ suites: '`)
   and read `T_max` from `tests_elapsed_s`; `tests=success` is not required at this commit.
3. **Derive.** `tests_step = max(30, roundup5(1.5 * T_max))`; `job = tests_step + infra_step + 15`;
   Sentry `max_runtime_minutes = job`, `checkin_margin_minutes = job + 25`. Replace the obsolete
   24m37s figure in the TIMEOUT BUDGET comment block with the measured `T_max`, the run id, the worked
   arithmetic and the two cross-check bounds, and state that the figure is uncensored.
4. **Final commit** (separate from the measurement commit): the derived ceilings in the workflow, and
   the two numbers plus corrected comments in `cron-monitors.tf`.
5. **Infra step.** The same dry run measures it (the measurement commit also raises the infra ceiling,
   to 45 min, which is free because it is the same run). If PR #9383 has merged, derive
   `infra_step = max(10, roundup5(1.5 * I_max))` from `infra_elapsed_s`. If it has not, the #9379 stall
   inflates the figure: derive from `infra_elapsed_s` minus the elapsed time of the suites #9379 names
   (read from the per-suite `PASS`/`RED` timestamps in the run log; reading only, no change to those
   suites) and say so in the derivation comment. If the infra step is killed even at 45 min, leave its
   ceiling untouched and file the conditional follow-up (Deferrals) instead of guessing. Without an
   infra fix the Sentry check-in stays `error` on every run (status is `ok` only when both steps
   succeed) and each run raises a Sentry issue (`failure_issue_threshold = 1`); that residual is
   stated in the PR, not hidden.

### Phase 4 — Verification and ship

- Run `bash plugins/soleur/test/main-health-monitor-workflow.test.sh`, `bash scripts/lint-diagnosis-claims.sh`
  (ratchet must not rise), `python3 scripts/lint-guard-contract.py`,
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own
  invocation), and `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts`
  (the existing suite that reads `cron-monitors.tf`).
- Also run `bash scripts/test-all-killed-classification.test.sh` (its A1c extracts the monitor's
  `[KILLED]` regex with `grep -oE ... | head -1`, so no new comment may quote that regex before the real
  line) and `bash plugins/soleur/test/scripts-shard-totality.test.sh`; re-measure the monitor test's
  duration against its `scripts/suite-durations.tsv` row (520 s, shard leg 5 in
  `scripts/suite-shard-legs.tsv`), since the added rows run in two shell arms.
- Before merge, post a corrective comment on #8112 (the diagnosis: control-line misread and
  budget exhaustion; the 76 earlier comments repeat the mislabelled claim) so the closed issue carries
  its own retraction.
- PR body: `Closes #8112`, a Changelog section, and an explicit residual note: any remaining red after
  merge is the infra step (a step killed at its ceiling reads as "terminated", arm 3) and is tracked
  separately; it will surface under its own accurate title via the corrected classifier rather than
  under #8112.
- Post-merge: confirm `apply-sentry-infra.yml` succeeded for the merge commit and that
  `apply-web-platform-infra.yml`'s run for it planned no change; dispatch a non-dry-run
  `gh workflow run main-health-monitor.yml`, arm a watch, and read the `SOLEUR_MAIN_HEALTH` annotation.

## Files to Edit

- `.github/workflows/main-health-monitor.yml`: classifier, tail de-duplication, arm-4 actions,
  elapsed annotation, ceilings and derivation comments, header defect list.
- `plugins/soleur/test/main-health-monitor-workflow.test.sh`: new assertion (8g), new fixtures and
  rows, Sentry parity guard, raised anti-vacuity floor.
- `apps/web-platform/infra/sentry/cron-monitors.tf`: `main_health_monitor` `max_runtime_minutes`,
  `checkin_margin_minutes` and the stale "65" comments.

## Files to Create

- None (fixtures are generated inside the test file, matching `fx-killed.txt` practice).

The pipeline also writes `knowledge-base/project/specs/feat-one-shot-8112-main-branch-tests-failing/tasks.md`,
this plan, and `knowledge-base/INDEX.md` if regenerated; a diff-scope check must allow them.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` over 87 issues; none names any of the three
files above.)

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Only fix the classifier, leave ceilings | Rejected: the monitor would then file an accurate "did not complete" tracker every six hours; the actual defect would remain. |
| Only raise ceilings, leave the classifier | Rejected: the next ceiling hit (the suite set keeps growing) would again title itself "tests failing" and name controls. |
| Raise ceilings without the Sentry envelope | Rejected: a healthy run would exceed the 90-min margin and page a missed check-in on a green main. |
| Shard the monitor across parallel legs (ADR-240 manifest) | Deferred to #9410; correct long-term structure, too large for a P1 repair. |
| Read the latest main CI conclusion instead of re-running the suites | Out of scope; recorded in #9410 as a variant to evaluate. |

## Deferrals (tracked)

- #9410: shard the monitor's tests step (and evaluate reading main CI instead of re-running it).
  Numeric trigger recorded there: a second ceiling raise, or a measured tests step above 60 minutes.
- Re-derive the infra step ceiling once #9379/#9383 land, if Phase 3 step 5 is skipped (filed at work
  time only in that case, `blocked-by` #9383).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; a founder reading the
  `ci/main-broken` tracker sees a wrong or missing statement about main's health.
- **If this leaks, the user's data is exposed via:** the public issue body channel; the removed raw
  `tail -30` append is the one path by which unfiltered per-suite diagnostics could reach a public
  issue, and the plan closes it with a regression row. No credential or user data is newly handled.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: CI monitor reporting logic and Sentry cron-monitor timing parameters only; no user data, credential, billing or user-facing surface is touched.`

## Observability

```yaml
liveness_signal:
  what: Sentry monitor main-health-monitor terminal check-in (sentry-heartbeat action) plus the SOLEUR_MAIN_HEALTH step-outcome annotation emitted on every run
  cadence: every 6 hours (Inngest dispatch, 0 */6 * * * UTC)
  alert_target: Sentry cron-monitor issue alert (routing in cron-monitor-alerts.tf) and the ci/main-broken GitHub tracker
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor.main_health_monitor) and .github/workflows/main-health-monitor.yml (final Sentry check-in step)

error_reporting:
  destination: GitHub issue tracker (label ci/main-broken, marker soleur:main-health-monitor) and the Sentry monitor error check-in
  fail_loud: "::error::Main branch health check did not pass (tests=<outcome> infra=<outcome>)" in the workflow run log, plus the arm-specific tracker title

failure_modes:
  - mode: a suite step ends at its ceiling without the runner printing a breakdown
    detection: workflow run log and the ::notice SOLEUR_MAIN_HEALTH annotation show a non-success outcome with no elapsed seconds; the filer selects arm 4 (title "did not complete") for the tests step, or arm 3 (terminated) when the infra capture carries the runner's killed line; the Sentry monitor receives status error
    alert_route: ci/main-broken tracker comment via the workflow run (::error::) and Sentry monitor error check-in
  - mode: Sentry max_runtime or margin drifts from the workflow job ceiling
    detection: the parity guard in plugins/soleur/test/main-health-monitor-workflow.test.sh fails the blocking scripts shard (workflow run log of the PR check)
    alert_route: red required check in the PR workflow run that introduces the drift
  - mode: dispatch dropped or runner never starts
    detection: Sentry monitor missed check-in after the derived margin (no workflow run exists, so no run log)
    alert_route: Sentry monitor alert to ActiveMembers

logs:
  where: GitHub Actions workflow run log (gh run view <run-id> --log) and the check-run annotations
  retention: 90 days (GitHub default for this public repository)

discoverability_test:
  command: grep -o -m1 tests_elapsed_s .github/workflows/main-health-monitor.yml
  expected_output: tests_elapsed_s
```

Known window, accepted: between the workflow merge and `apply-sentry-infra.yml` finishing, the old
90-minute margin applies to a run that may last longer; the post-merge check confirms the apply
succeeded before the next 6-hour boundary (a false missed-check-in email in that window is the cost
of the ordering and is not a main-health signal).

## Encryption Posture

This plan introduces no persistent data store and no new cross-component connection. The only `.tf`
edit changes two numeric parameters on an existing Sentry cron-monitor resource and rewrites comments.

```yaml
at_rest: []
in_transit: []
```

## Guard Contract

### Guard 1 — monitor arm selection (what the tracker is allowed to claim)

**Property.** A run is titled "main branch tests failing" only when the runner itself reported a failure: a `RED`/`UNACCOUNTED` line, or a printed breakdown line with at least one failed suite; anything else with a non-success step outcome is reported as "did not complete" with only the measured outcome.

**Assembly.** The classification quantifies over both captures (`/tmp/tests-output.txt` and `/tmp/infra-output.txt`) through the single `for pair in "tests:..." "infra:..."` loop in the filer step; the verdict flows through one chokepoint, the `HAS_FAIL_MARKER` / `HAS_KILLED_MARKER` arm chain, into three consumers: the new-issue body, the existing-tracker comment, and the retitle (`gh issue edit --title`), all reading the same `TITLE`/`HEADING`/`LEDE`/`ACTIONS`. Excerpt text reaches the public body through the filtered tail append and the display-hit append (the raw tail append is removed), all before the redaction pass. The harness extracts the filer's `run:` body from the YAML and executes it, so its own dispatch is the extraction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-admit bare `^\[FAIL\]` as a verdict input (`fx-controls-zero-failed.txt` and the live-shape `fx-fail-no-breakdown.txt` select the failing arm) | RED |
| 2 | Weaken the breakdown regex to `[0-9]+ failed` (drops the `[1-9]`; the 0-failed controls fixture selects arm 2) | RED |
| 3 | Second member after a compliant first: tests capture is controls-only with `0 failed`, infra capture holds a `RED` line; a loop that stops at the first capture yields arm 4 instead of arm 2 | RED |
| 4 | Reintroduce the unfiltered `$(tail -30 "$file")` append (SOLEUR leak and duplicated tail) | RED |
| 5 | Dispatch: neuter the extraction (empty filer body, no `gh issue create`); the existing extraction assertions and the raised anti-vacuity floor must fail, not report zero rows | RED |
| 6 | Must-PASS non-canonical input: `fx-fail-corroborated.txt` (spaced label, `log=` suffix, 2 failed) and `fx-red-only.txt` must select arm 2 and `fx-infra-killed.txt` arm 3, so a classifier that rejects everything is caught | PASS |

**Anchor.** A suite could in principle print a forged breakdown line; the same residual is already accepted and recorded for the `[KILLED]` arm, and it only affects a run whose step outcome is already non-success. The regex requires the runner's exact `=== N suites: P passed, F failed, K killed (` shape, and the test derives that shape from the `=== $suites suites:` echo in `scripts/test-all.sh` so a runner-side rename reds the suite.

### Guard 2 — Sentry envelope parity (the three numbers move together)

**Property.** The Sentry cron monitor's `max_runtime_minutes` equals the workflow's job-level `timeout-minutes` and its `checkin_margin_minutes` is at least that ceiling plus 25 and under 360.

**Assembly.** Two sources and one relation: the workflow's single job-level `timeout-minutes` (the line indented four spaces under `health-check:`) and the `sentry_cron_monitor "main_health_monitor"` resource block in `apps/web-platform/infra/sentry/cron-monitors.tf`, found by resource name, not by line number. Any other resource carrying that `name` would be a second member; the test asserts exactly one block with `name = "main-health-monitor"` (after stripping `#` comment lines) and fails closed if it cannot be found.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Raise the workflow job ceiling by 5 without touching Terraform | RED |
| 2 | Lower `checkin_margin_minutes` to job + 24 | RED |
| 3 | Add a second `sentry_cron_monitor` block (distinct resource label, same `name = "main-health-monitor"`) after a compliant first and mutate only the second | RED |
| 4 | Dispatch: rename the resource so the block is not found; the guard must report "block not found", not pass over zero blocks | RED |
| 5 | Must-PASS non-canonical input: margin of job + 40 (larger than the minimum) with `max_runtime_minutes == job` | PASS |

**Anchor.** Workflow and Terraform are editable in one diff, so this proves consistency, not that the numbers are right. The independent anchors are the Phase 3 uncensored measurement recorded in the workflow's derivation comment (run id) and the `apply-sentry-infra.yml` plan on merge, which shows the monitor resource changing.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` exits 0 and prints `0 failed`; its
      anti-vacuity floor equals the new dispatched count and the PR names the number.
- [ ] Replaying the #8112 capture (`fx-controls-zero-failed.txt`) through the extracted filer yields the
      title `CI: main-branch health check did not complete`, not `CI: main branch tests failing`, under
      both `-e` and `-eo pipefail` (a harness row).
- [ ] `fx-fail-corroborated.txt` and `fx-red-only.txt` still yield `CI: main branch tests failing`.
- [ ] The published body has the capture tail exactly once and zero diagnostic lines
      (`grep -c '^SOLEUR| ' <body>` is `0`; anchored, because the body quotes the `grep 'SOLEUR| '` hint).
- [ ] `grep -cF 'SUMMARY="${SUMMARY}$(tail -30 "$file")"' .github/workflows/main-health-monitor.yml` is `0`.
- [ ] One uncensored dry run of the branch workflow (step ended before its raised ceiling and the
      runner printed its breakdown) is recorded in the workflow's derivation comment with its run id and
      `tests_elapsed_s`; `gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[].message'`
      for that run prints a `tests_elapsed_s=<n>` equal to the recorded figure, and the figure lies in
      about 40 to 70 min or the discrepancy is explained in the comment.
- [ ] Workflow ceilings satisfy `tests_step >= max(30, roundup5(1.5 * T_max))`,
      `job >= tests_step + infra_step + 15` and `job < 360`.
- [ ] `sentry_cron_monitor.main_health_monitor` has `max_runtime_minutes == job` and
      `checkin_margin_minutes == job + 25`; `grep -c -e 'timeout-minutes: 65' -e '65 (job ceiling)' -e 'ceiling is 65' apps/web-platform/infra/sentry/cron-monitors.tf` is `0`.
- [ ] `python3 scripts/lint-guard-contract.py` passes with this plan present, `bash scripts/lint-diagnosis-claims.sh`
      does not raise the ratchet, and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes.
- [ ] `git diff --name-only origin/main...HEAD` lists no path matching `git-data` or `apt-bounded`, and
      the only `apps/web-platform/infra/` path is `sentry/cron-monitors.tf`.
- [ ] A corrective comment is posted on #8112 before merge; the PR body contains `Closes #8112`, a
      `## Changelog` section and the residual-infra note.

### Post-merge (agent-run, no human step)

- [ ] `apply-sentry-infra.yml` for the merge commit concluded `success` before the next 6-hour boundary with only
      `sentry_cron_monitor.main_health_monitor` changing; `apply-web-platform-infra.yml`'s run for it
      planned no resource change.
- [ ] A non-dry-run dispatch after merge reports `tests=success` in the `SOLEUR_MAIN_HEALTH` annotation.
      `Closes #8112` already closed the issue at merge, so a `tests` result other than `success` reopens
      #8112 with the run id as evidence; if `infra=failure`, the filed or commented tracker carries an
      arm-accurate title ("terminated", arm 3) and is not labelled "tests failing".

## Test Scenarios

- Given the #8112 capture (7 expected-control `[FAIL]` lines, breakdown `0 failed`), when the filer runs
  with `TESTS_OUTCOME=failure`, then the title is the "did not complete" arm and the body names no suite.
- Given a `[FAIL]` line and no breakdown (step killed at its ceiling), then arm 4 and no revert action.
- Given a `[FAIL]` line with `2 failed` in the breakdown, then "tests failing".
- Given a tests capture of controls only and an infra capture with a `RED` line, then "tests failing".
- Given a capture whose last 30 lines include `SOLEUR| ` lines, then the body has none and one tail.
- Given the Sentry margin set to job + 24, or the block missing, then the static test is RED.
- Regression for this bug: every row above is the regression set for #8112 (controls misread, timeout
  mislabel, raw-tail leak, Sentry drift).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI/infrastructure tooling change. The Terraform edit is two
numeric parameters on an existing monitor, applied by the existing `apply-sentry-infra.yml` pipeline.

## Dependencies & Risks

- **Wall time.** One dry run of ~50-75 min; arm a watch.
- **Dry-run limits.** `dry_run=true` skips the filer, so the live filer path is covered by the
  behavioural harness and the post-merge dispatch, not by the dry run.
- **Infra step coupling.** Its measurement is distorted by #9379 until PR #9383 merges; the plan
  measures it in the same dry run, subtracts the named stalled suites (reading only), and degrades to
  "leave untouched, file the follow-up" rather than guess. A `[KILLED]` of the nested infra runner at
  its step ceiling renders under arm 3 ("terminated"), whose generic actions name a suite; that
  wording is recorded in #9410 as a residual, not changed here.
- **Sentry apply.** `apply-sentry-infra.yml` runs a full-root plan; confirm it is the single monitor change.
- **Closes semantics.** `Closes #8112` is justified by: classifier fixed plus tests step measured green.
  If infra remains red after merge, the corrected classifier files a new, accurate tracker instead of
  reusing #8112's wrong title.
- **Shelf life.** The 1.5x ceiling still tracks suite growth; #9410 carries the structural fix and the trigger.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan; this
  one carries `none` with the scope-out reason.
- The dry-run measurement is uncensored only if its ceiling exceeds the need; if the run is itself
  killed at the raised ceiling, raise again and re-run; never derive from it.
- `steps[].conclusion` is pinned to `success` by `continue-on-error`; read verdicts from the
  `SOLEUR_MAIN_HEALTH` annotation (the step `outcome`), never from `gh run view --json jobs` conclusions.
- Do not push the Terraform commit before the dry run exists; the diff gate would run the nested infra
  runner inside the tests step and inflate the measurement.
- The anti-vacuity floor in the test file is a lower bound (`TOTAL < MIN_ASSERTIONS` fails), so raising
  it to the new count is what makes the added rows non-droppable; every behavioural row runs in two shell
  arms (`-e`, `-eo pipefail`), so count rows x 2.
- Fixtures must keep both orphan shapes distinct (breakdown with `0 failed` vs no breakdown); do not
  collapse them into one.

## References & Research

- Issue #8112; draft PR #9408 (this branch); #9379 / draft PR #9383 (apt stall, out of scope); #9410
  (sharding, deferred).
- Run logs: 34726833667 (issue run), 36903587088 (latest at planning time).
- ADR-166 (a CI message may only name a cause the job measured); #7307, #7371, #7376, #7425, #7429,
  #8431, #8993 (monitor history); ADR-240 (shard manifest, basis of the deferred sharding).
- `.github/workflows/main-health-monitor.yml`, `plugins/soleur/test/main-health-monitor-workflow.test.sh`,
  `apps/web-platform/infra/sentry/cron-monitors.tf`, `scripts/test-all.sh` (`[FAIL]` line at the
  `run_suite` tail; breakdown line at the `=== $suites suites:` echo; parent-death watchdog at the
  `parent process gone` message).
