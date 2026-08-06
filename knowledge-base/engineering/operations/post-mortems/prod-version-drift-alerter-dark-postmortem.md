---
title: "The production-staleness alarm was dark on exactly the two verdicts it exists to raise — inherited errexit killed the capture, and a second alarm was dark the same way"
date: 2026-08-06
incident_pr: 7305
incident_window: "2026-08-05 ~09:18 UTC → 2026-08-06 (scheduled-prod-version-drift: 8 consecutive scheduled runs failed with zero output at first measurement, 12/12 by review time; scheduled-cron-artifact-age: 6 consecutive daily ticks, 2026-07-31 → 2026-08-05). Both alarms were structurally unable to report for the whole window."
recovery_at: "2026-08-06 (PR #7305 — `set +e` at 17 sites, the empty-string coercion conjunct at 6 consumers, and a repo-wide lint gate; verified post-merge by a dispatched run reaching a real verdict)"
suspected_change: "Latent since each alarm was authored. GitHub invokes a `run:` step with no `shell:` key as `bash -e {0}`, so errexit is inherited; the house-standard opening line `set -uo pipefail` only ADDS flags and never cleared it. Every affected step then died AT its `out=\"$(...)\"; rc=$?` capture. Surfaced now because the checker began returning non-zero — i.e. the alarms went dark at precisely the moment they had something to say."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - observability (production-staleness alarm; scheduled-cron artifact-age alarm)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability/observability only. No personal data was accessed,
# altered, lost or disclosed — the failure mode is a monitoring step aborting before it can
# write its own output. No store, endpoint, credential or data flow is involved on either the
# broken or the fixed path. Art. 33/34 therefore do not trigger; recorded explicitly rather
# than left blank because the `single-user incident` threshold requires the evaluation to be
# on the record. The threshold is `single-user incident` because the operator is a single
# non-technical founder for whom "my merged fixes are not live and nothing told me" is the
# brand-survival failure this alarm exists to prevent.
---

# PIR — the production-staleness alarm was dark on exactly the two verdicts it exists to raise

## Summary

`scheduled-prod-version-drift.yml` is the alarm that tells the operator production is serving an
old build. It failed **8 of 8** scheduled runs at first measurement (12/12 by review time),
emitting **zero** diagnostic output — no verdict, no issue, no email, and a Sentry check-in that
reported the monitor as broken rather than reporting drift.

The same defect had also taken `scheduled-cron-artifact-age.yml` dark for **6 consecutive daily
ticks** (2026-07-31 → 2026-08-05). Nobody noticed, because a dark alarm and a healthy one look
identical from outside.

## Impact

- **Production staleness was unmonitored for the whole window.** Releases were independently
  blocked by the zot registry outage, so production plausibly *was* behind — meaning the alarm
  was dark precisely during the episode it exists to catch.
- **The operator received a mis-attributed signal.** With the check step aborting,
  `steps.check.outcome` was `failure`, so the Sentry cron monitor checked in `status=error` on
  every run. The operator was told *"the monitor is broken"* when what had been measured was
  drift — an AP-021 (ADR-166) diagnostic-honesty violation.
- **A second alarm (cron artifact-age) was dark with no channel at all** — it has no Sentry
  heartbeat, so its only signal was a red scheduled run nobody watches.
- No user-facing outage, no data exposure. The blast radius is "the operator would not have been
  told", which for a solo non-technical founder is the whole point of the alarm.

## Root cause

GitHub invokes a `run:` step that declares no `shell:` key as `/usr/bin/bash -e {0}`. Errexit is
**already on** before the body's first line, and the repo's standard opening line
`set -uo pipefail` only *adds* flags — it cannot clear one.

So this idiom does not do what it reads as doing:

```bash
set -uo pipefail
out="$(bash scripts/prod-version-drift-check.sh 2>&1)"; rc=$?
```

On a non-zero exit the shell dies **at the capture**. `rc=$?` never runs, `$GITHUB_OUTPUT` is
never written, and every downstream branch — verdict parse, `::error::`, issue filing, email,
heartbeat gating — is unreachable.

The checker's contract makes the failure maximally perverse:

| exit | verdict | intent | under inherited `-e` |
|---|---|---|---|
| 0 | `CLEAN` / `DRIFT_PENDING` | no alert | works, unchanged |
| 1 | `DRIFT_SUSTAINED` | **ALERT** | step dies, silent |
| 2 | `CHECK_ERROR` | **ALERT** | step dies, silent |

Errexit killed **exactly the two alerting verdicts** and let the quiet one through. The alarm was
silent when it had nothing to say and dark when it did.

### A second, independent defect found while fixing the first

GitHub Actions `==` is **loose**: operands of differing types are cast to Number, an unset step
output is `''`, and `''` casts to 0 — so **`'' == '0'` is TRUE**. A step that dies before writing
`$GITHUB_OUTPUT` therefore satisfies every `== '0'` gate downstream.

Measured on run `31054501973`: the step that **files** the "checker is broken" issue (gated
`!= '0' && != '1'`) was **skipped**, while its exact logical complement — the step that **closes**
it (gated `== '0' || == '1'`) — **ran**. On any dead tick the workflow would auto-close the issue
reporting its own breakage, posting *"the checker is evaluating again (verdict: )"* with an empty
verdict. `set +e` does **not** fix this; it survives the errexit repair and re-arms on any future
abort.

The same coercion left `infra-validation.yml` fail-open: its plan step carries
`continue-on-error: true` and its job-failing guard reads `exit_code != '0'`, which is **false**
on an empty output — so a failing production `terraform plan` could report green.

## Why it was not caught

- **The test suite could not see it.** All 49 Part B assertions were regexes over source. None
  executed the step body, and a grep cannot observe a step *dying*.
- **The clean path passed throughout.** Measured: against the pre-fix workflow the suite reports
  133 pass / 18 fail, and **every exit-0 assertion is green**. Any verification that exercised
  only the CLEAN path — the natural thing to do — would have looked correct for the entire outage.
- **Prose was the whole prior enforcement.** This is the **sixth** occurrence of the class. Four
  learnings, several in-workflow comments and two hand sweeps preceded it; the most recent sweep
  was **six days** earlier (`447211a1a` 2026-07-30T22:40 → `1af49f532` 2026-08-06T01:40).
- **The workflow documented the intent it failed to achieve.** Its own comment reads *"The
  checker's exit code is DATA, not a job failure."* Correct reasoning, unimplemented.

## Resolution

1. `set +e` at **17 sites across 7 files**, found by a repo-wide sweep of all 697 `run:` bodies
   and confirmed by three independent methods. Narrow brackets where a body-wide clear would
   disarm unrelated logic (`scheduled-inngest-health.yml` drives an automated prod restart).
2. `steps.check.outcome == 'success' &&` on all six consumers of the check step's outputs, plus
   an `always() && (outcome != 'success' || exit_code != '0')` guard at `infra-validation.yml`.
3. Two comments asserting `-e` was "intentionally omitted" corrected — they are the propagation
   vector, and one was the stated justification for the Sentry heartbeat expression.
4. `scripts/lint-workflow-errexit-capture.py` (ADR-170 / AP-022), registered in `test-all.sh` and
   calibrated in both directions: **17 findings on `origin/main` → 0 on the fixed tree**, no
   `.highwater`.
5. The test harness now **executes the shipped step body** under `bash -e` on all three verdicts,
   with mutation axes proving the assertions are not vacuous.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7311 | Widen the gate to the 13 latent `-z`-guarded assignment sites (5 inherited / 8 explicit `set -euo pipefail`); the explicit half needs its own separately-justified rule | agent |

## Lessons

1. **An alarm's failure mode is silence, so "no alert" is not evidence of health.** Both alarms
   were dark for days and looked identical to healthy ones. Any monitor whose failure path is
   "emit nothing" needs an independent liveness channel — `scheduled-cron-artifact-age.yml` still
   has none, which is why its 6 dark ticks went unnoticed.
2. **Verify a fix on the path that was broken, not the path that was working.** The CLEAN arm
   passed unchanged against the broken body for the entire outage. A fix — or a test — verified
   only there is indistinguishable from no fix.
3. **A guard whose enforcement is prose will recur.** Six occurrences, four learnings, six-ish
   in-workflow comments, two hand sweeps, then a recurrence six days later. The mechanical gate is
   the first intervention of a different kind.
4. **The repair for one silent-failure class can ship another.** The sweep's own `|| true` on a
   `gh issue list` capture collapsed "lookup failed" into "nothing found" — in the same PR that
   restores four handlers whose comment reads *"A FAILED LOOKUP IS NOT 'NOTHING FOUND'"*. Caught
   at review. Full detail:
   `knowledge-base/project/learnings/2026-08-06-the-gate-i-built-to-catch-a-blind-spot-had-the-same-blind-spot.md`.
