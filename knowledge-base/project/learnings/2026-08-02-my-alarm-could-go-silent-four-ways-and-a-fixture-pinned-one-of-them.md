---
module: prod-version-drift-check / sentry-cron-monitors
date: 2026-08-02
problem_type: logic_error
component: shell_script
symptoms:
  - "a green 79-assertion suite let 16 of 20 new mutations through"
  - "a fixture asserted the alarm's own silence as intended behaviour"
  - "a cron monitor margin no dispatch on this repo has ever met"
  - "an alerting channel that was serially downstream of the channel it was meant to back up"
root_cause: unverified_assertion
severity: high
tags: [alerting, fail-closed, mutation-testing, measurement, cron, precedent]
synced_to: [review, work, plan]
---

# My alarm could go silent four ways, and a fixture pinned one of them

Ten review agents on a PR whose entire thesis is *"this alarm will not go quiet"* (#7091, the
production version-drift alerter). The classifier was fine — the invariant, `--first-parent`,
the oldest-commit clock, direct `rc` capture and the sanitisation were all independently
verified sound. **Every defect was in the alerting state machine or in what the tests could
see.** That distribution is the lesson: I had spent the effort where the thinking was
interesting, and the alarm's actual reliability lived in the wiring.

## 1. A PRECEDENT'S CONSTANT IS NOT EVIDENCE — measure the thing it claims

I set `checkin_margin_minutes = 30` on a `*/30` monitor, citing an in-file comment that
`margin == interval` "MAXIMIZES jitter tolerance ... so ordinary GHA dispatch drift cannot
false-page", and pointing at two live monitors using it. Measured:

```
$ gh run list --workflow=scheduled-zot-restart-loop.yml --event=schedule --limit 60
  n=59 consecutive scheduled runs of the */30 sibling
  min=61  median=114  max=243   (minutes between runs)
  gaps within the 60-minute (tick + margin) window: 0 of 59
```

Not "occasionally late" — **never once inside the window.** So the margin puts the monitor in a
missed-check-in state on essentially every tick; Sentry's cron route pages on
`New/ExistingHighPriorityIssueCondition` (first-seen or escalated-to, never recurrence), so the
founder's ONE page is spent on jitter within hours and a genuinely dark alarm is then
indistinguishable from the standing noise. The monitor's own margin reintroduced the exact
failure the monitor exists to detect.

The two cited precedents are not validated precedents — they are two monitors that must be
permanently missed, invisible *because of* the same suppression. **A constant copied from a
sibling inherits the sibling's untested assumption, and a comment asserting a property is not a
measurement of it.** My own diff even contained the refutation: the checker's header cites the
real jitter (median 80-134 late, max 339) as the reason the clock reads a commit timestamp
instead of counting ticks, while the `.tf` comment I wrote denied the same jitter mattered.
*When two files in one PR disagree about the same platform, at least one is prose.*

Corollary for review: when several agents concur, ask what model they share. One agent rated the
margin "correct and precedent-consistent" — reasoning from the same in-file comment I had. Two
others measured. Measurement beat concurring inference.

## 2. A FIXTURE CAN PIN THE BUG

`A19` asserted `rc=0` for a future-dated commit, with the comment *"must not underflow into a
huge age and page."* The underflow concern was real and the remedy was backwards: `%ct` is
committer-settable, the clock takes the numeric MINIMUM, so one bad timestamp decides the
verdict. Negative age never exceeds the threshold, so three provably undeployed commits returned
`DRIFT_PENDING` / exit 0 — no issue, no email, and the heartbeat checking in `ok`.

The test did not miss this. **The test asserted it.** A fixture that encodes the safe-looking
direction of a fail-open is worse than no fixture, because it converts the defect into a
documented contract that a later reader must argue against. Litmus for any guard whose job is to
alert: *name the input under which this returns "healthy" while the watched condition is true* —
and check whether a fixture already blesses it.

Both directions now fail closed, plus `A19e` (a genuinely 3-day-old commit still pages) so the
guard cannot become a blanket rejection.

## 3. "TWO INDEPENDENT CHANNELS" IS A CLAIM ABOUT CONTROL FLOW

The plan described the email and the GitHub issue as independent alert channels. The email step
was gated `steps.issue.outputs.first_detection == 'true'` — so a dead issue step meant the
operator was never told production was stale, only that a monitor was unhealthy. Independence
asserted in prose, serial dependency in the `if:`.

Same family, one layer up: the heartbeat required `delivered == '1'`, and on tick 2+ of a
sustained outage the email is *correctly* skipped by the anti-spam gate — a skipped step's
outputs are EMPTY, not `'0'`. So the monitor reported ITSELF broken for the duration of every
real incident, making monitor-health and prod-health the same bit and disabling the liveness
channel exactly when a genuine checker failure would need to page.

**For any multi-channel alert, draw the actual step graph and ask which channel's failure takes
another channel down with it.** The fix in both cases was to distinguish "no alert was required"
(positively identified) from "an alert was required and did not happen" (everything else,
including empty).

## 4. A GUARD THAT CLOSES ON A UNION CLOSES TOO MUCH

Close-on-recovery was gated `exit_code == '0'`, which is CLEAN **∪** DRIFT_PENDING. It therefore
closed the drift issue while commits were still undeployed, posting "production is no longer
missing any commit" — contradicted by the verdict interpolated into the same sentence. And
because one label-wide closer served two issue classes with two different recovery conditions, a
*resolved* check-error issue could never close while a drift was sustained (exit is 1
throughout), so it sat open, lying, for exactly the window the operator reads these issues.

Filing was already per-class (title-scoped); only closing was label-wide. **When filing is
per-class and closing is not, that asymmetry is the bug.**

## 5. AUDIT THE BATTERY'S AXES, NOT ITS SCORE

My battery reported 10/10 caught. An adversarial pass found **16 of 20 new mutations surviving**,
because the ten axes sampled few classes:

- **`main()` had zero coverage.** Repointing the default health URL at *staging* — the alarm then
  monitors the wrong host forever while looking perfectly healthy — passed. So did cutting the
  retry to one attempt, and renaming any output key.
- **Part B read only `if:` and `uses.with`.** Renaming `id: notify`, or deleting an `env:`
  DECLARATION (killing the step mid-body under `set -u`, silently suppressing the drift email),
  were invisible.
- **`exit_code == '2'` appeared nowhere in the suite**, so both check-error steps were deletable.
- **The heartbeat's value mapping was unasserted** — swapping `&& 'ok' || 'error'` makes Sentry
  report error when healthy and ok when broken, with every asserted token still present.

And **axis 2 was vacuous for its entire life**: its regex `PATHSPEC=\([^)]*\)` stopped at the `)`
inside `':(exclude)…'`, emitting unparseable bash. It was caught by `A0` ("is the checker
sourceable") — the weakest possible mutant — and never exercised pathspec parity at all. It
scored as a pass every run.

Two structural fixes, both worth generalising:

1. **`mutate_and_assert_red` takes the label of the assertion it expects to fail** and greps the
   child's output for it. That converts "something went red" into "the property under test went
   red", and it exposed axis 2 immediately. This is the same anchoring discipline the repo
   already applies to greps, applied to mutations.
2. **Per-part anti-vacuity floors.** A single global floor set below the real total is slack that
   hides a whole part: at 58 against 79, `if false; then` on the Part C dispatch deleted the
   entire battery — the suite's own anti-vacuity mechanism — and still exited 0.

Also: matchers now read comment-stripped bodies. Previously the workflow carried comments
*written to avoid tripping the tests*, which points the coupling backwards — a test's matcher
became a constraint on how the production artifact may be documented.

## Session Errors

1. **Ended a turn on "starting the P0 now" without starting it.** A forward-looking sentence as
   the last thing in a turn is an abandoned pipeline, not a handoff; the operator had to ask why
   I stopped. Documented in-repo, and I did it anyway.
2. **Broke the workflow YAML twice with multi-line strings.** A literal whose continuation lines
   start at column 0 terminates a `run: |` block scalar. Build such bodies by appending indented
   lines.
3. **Wrote apostrophes into a single-quoted bash heredoc.** `PYEXTRACT='…'` carries an embedded
   Python program; `test's` closed the string and the shell executed the prose. Any program
   embedded in single quotes must contain no apostrophe at all.
4. **Two rows of my own acceptance-evidence file went stale within the session** — recorded
   pre-fix and never re-derived, so they understated the suite. The file's own preamble demands
   the command's actual output. Re-derive evidence rows after every change that could move them,
   including changes made in the same session.
5. **Two CI failures were mine and were invisible to the gates I ran.** `test-all.sh` covers the
   scripts group and `run-registered-suites.sh` covers `infra/`; the `(c2)` monitor-registry
   guard lives in the webplat vitest suite, which only CI runs end to end. Three runners, two
   confirmed, and the diff's blast radius landed in the third.
