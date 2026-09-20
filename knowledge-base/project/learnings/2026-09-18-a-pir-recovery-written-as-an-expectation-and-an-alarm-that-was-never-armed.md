---
date: 2026-09-18
category: machinery
module: post-mortems-and-cron-monitors
related:
  - knowledge-base/engineering/operations/post-mortems/2026-08-13-marketplace-drift-monitor-dark-since-creation-postmortem.md
  - .github/workflows/scheduled-marketplace-drift.yml
  - .github/actions/sentry-heartbeat/
  - scripts/lint-workflow-local-action-checkout.py
---

# Learning: a PIR `recovery_at` written as an expectation, and a configured alarm that had never been armed

## Problem

The 2026-08-13 post-mortem for `scheduled-marketplace-drift`'s dark Sentry monitor recorded
`recovery_at: "2026-08-13 — the three composite inputs are forwarded; first live check-in
expected at the next 06:37 UTC tick"`, `status: resolved`, and `*No action items — incident
fully resolved in the source PR with no residual work.*`

The check-in never came. Measured 2026-09-18, 36 days later: all 36 scheduled runs after that
repair carry `Can't find 'action.yml' … Did you forget to run actions/checkout`, 33 of them
concluded `success`, and `GET /monitors/scheduled-marketplace-drift/checkins/` returned `[]`
while the monitor itself reported `status: active`.

Two independent causes, and the PIR named only the first.

## Root cause

**The resolution-form defect.** `drift-check` is deliberately checkout-free; a `uses: ./…`
action resolves from the runner's workspace, which that job never populates. `continue-on-error:
true` — correct at that step, so a Sentry blip cannot red a healthy probe — turned the runner's
resolution error into a green step. That class is documented in
[the sibling learning](2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md);
this file does not restate it.

**The alarm was itself inert, and nothing recorded that.** The monitor carried
`checkin_margin: 360` and `failure_issue_threshold: 1` on a daily schedule. Thirty-seven missed
ticks produced **zero** Sentry issues. A cron monitor tracks missed check-ins *per environment*,
and with no check-in ever received its `environments` list was empty — so there was no
environment to miss. Measured both states in one session: `environments: []` before, and
`[{name: production, status: ok, nextCheckIn: 2026-09-19T06:37:00Z}]` after the first check-in
armed it. A 90-day issue query for the monitor returns `[]`.

So the configured backstop was not a second line of defence that happened to be bypassed. It
could not fire until fed, and it returns to inert if the monitor is ever recreated.

## The two novel points

**1. A `recovery_at` written as a future expectation is not a measurement.** The 2026-08-13
repair's verification read the step and run conclusion — which `continue-on-error` guarantees
green regardless — and then wrote the expected consequence into the PIR as though it were an
observation. The sentence was never true, and because the PIR said `resolved` with no action
items, nothing re-opened the question for 36 days. A PIR's recovery field must carry a value
read back from the affected path's own telemetry (here: a check-in row, with its id), or the
field should say the recovery is unverified. The corpus already says recovery is evidenced by
the path's own telemetry
([2026-06-30](2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md));
what this adds is that the PIR field itself is where the unverified claim gets laundered into
fact.

**2. An ingest 2xx is not a recorded check-in, and a configured alarm is not an armed one.**
Sentry's cron ingest endpoint accepts an unknown monitor slug and answers 202 — the sibling
`scheduled-devin-docs-drift` monitor does not exist in Sentry at all (its infra apply failed,
tracked in #8282) and its repair's 2xx proved nothing. The only evidence that a monitor is
receiving check-ins is a row from `GET /monitors/{slug}/checkins/`; the only evidence that its
margin will fire is a non-empty `environments` list. Both are one authenticated read.

## Prevention

- When a PIR's `recovery_at` cannot be measured at write time, say so in the field. Do not write
  the expected consequence in the past or present tense.
- For any heartbeat/monitor repair, gate DONE on a check-in row (id, status, environment,
  dateCreated), never on a run or step conclusion — and never on the ingest response either.
- When reading a monitor as "configured to alarm", check `environments` is non-empty. A monitor
  that has never been checked in cannot miss a check-in.
- Distinguish a *resolution* proof from a *liveness* proof. This repair was verified by
  `workflow_dispatch`, and the heartbeat is ungated by event, so a dispatched check-in resets
  the margin exactly like a scheduled one. The scheduled path is only proven by a `schedule`-event
  row. (`scheduled-sentry-alert-drift.yml` gates its heartbeat on a dispatch input for this
  reason; that gate was deliberately not adopted here — a manual reconciliation run is a real
  evaluation of the manifest, and one dispatch masks at most one 6-hour window, not the
  weeks-long schedule-disabled mode the monitor exists for.)

**Closed 2026-09-20.** The liveness half is now measured, not owed: `schedule`-event runs
35440135873 and 35508695589 produced check-ins `b86e28dd-f6b0-4293-a90f-cb720d894b52`
(2026-09-19T11:27:55Z) and `3e307148-2590-4ecb-88fb-7138dc4d2c5b` (2026-09-20T11:46:41Z), with
the second run's `drift-check` log re-read as `http_code=202` and zero resolution errors. The
table is in the PIR's `## Addendum — 2026-09-20 (#8313)`. Both ticks ran ~4h50m behind the
`37 6 * * *` cron — GitHub queueing, inside `checkin_margin: 360` — which is a fact the dark
window had hidden: the margin had never been exercised by a real check-in.

## Session Errors

1. **The first branch dispatch failed `Set up job` on a committed dangling symlink.**
   `test/fixtures/orphan-proc-dangling/4242/{cwd,fd/255}` pointed at
   `/nonexistent-orphan-fixture/…`, and the `$/` reference form extracts the whole repository
   archive — so extraction aborted the job before any step ran, naming a fixture path unrelated
   to the change. — Recovery: removed both links (no runtime consumer; AC30b synthesizes them
   under `mktemp` on every run), documented why in the fixture README, re-dispatched.
   — **Prevention:** shipped as a control, not a comment — a `no-dangling-committed-symlinks`
   suite in `scripts/test-all.sh`, mutation-proven (a planted dangling link reds it by name).
   Any `$/` or `owner/repo/path@ref` self-reference depends on the whole archive extracting.

2. **A `$/` switch silently dropped the repaired workflow out of a guard's cohort.**
   `HEARTBEAT_USES_RE` in `sentry-monitor-iac-parity.test.ts` was `./`-anchored, so the one
   workflow the change repairs lost every shape assertion on the step it repairs. Neither
   neighbouring guard could see it: the closure check derives both populations from that same
   regex, and the floor read 13 ≥ 12. — Recovery: widened to `[.$]`, floor re-derived to 14,
   mutation-proven. — **Prevention:** when a change moves a site from one reference form to
   another, grep every consumer anchored on the OLD literal before moving it. The PR's own
   `SOLEUR-DEBT` marker enumerated four such consumers and omitted this one, which is why the
   marker now names the *criterion* plus the grep that derives the set, instead of a hand list.

3. **A verdict routed through a helper guarded the helper's body, not its call.** Replacing the
   trailing `verdict_ok "$FAIL"` with `true` printed 15 FAIL lines and exited 0 — CI green.
   — Recovery: the verdict rides an `EXIT` trap seeded to 2; forging or deleting the line now
   exits 2 (measured). — **Prevention:** "route it through a helper and test the helper" never
   covers the call site. For any suite whose exit status is a trailing command, ask what
   replacing that command with `true` does.

4. **A mutation run from a temp path measured the wrong guard.** `bash "$sb/m1.sh"` resolved
   `ROOT` outside the repo, hit the SUT-not-readable guard, and returned rc 1 — which read like
   a result. — Recovery: re-ran in place against a genuinely broken SUT; rc 2. — **Prevention:**
   a mutation of a path-sensitive script must run at its real path. Pair every mutation run with
   a control whose answer you already know.

5. **Two lints were invoked outside the scope CI uses.** `lint-trap-tempfile-ownership.py` with
   explicit `.py` paths matched prose in a docstring (its CI form walks tracked `*.sh` only);
   `actionlint` pointed at a composite `action.yml` parsed it as a workflow (CI scopes to
   `.github/workflows/`). Both "findings" were my invocation. — **Prevention:** run a gate in the
   form CI runs it, and read the invocation before reading the output.

6. **A new floor fired on every fixture because the filler predated it.** Adding
   `MIN_ACTION_FILES` made 24 of 40 assertions measure the floor rather than the rule.
   — Recovery: the filler tree now carries a clean composite, so both floors are cleared by
   design. — **Prevention:** when adding a floor to a guard, update the fixture that clears it in
   the same edit — otherwise every case measures the new floor.

7. **`git commit` stalled ~7 minutes on lefthook's `flock`,** waiting on the full-gate advisory
   lock held by a sibling worktree. — Recovery: killed my own lefthook (ownership verified via
   `/proc/<pid>/cwd`), committed with `LEFTHOOK=0`, and ran the linters it would have run
   explicitly, listing them in the commit message. — **Prevention:** already the sanctioned path
   for this repo; the omission to avoid is committing under `LEFTHOOK=0` without running the
   linters and saying which.

8. **Inherited counts and claims asserted without re-derivation.** The composite header said
   "13 sibling sites" (measured: 13 `./` steps across 12 files, 14 including the new `$/`); the
   lint header dated the devin-docs-drift repair 2026-09-17, a day on which that workflow did not
   yet exist. The planning phase also inherited two falsified claims (actionlint PR #732 reported
   merged — live: OPEN; a `workflow_dispatch` learning misapplied to an on-`main` workflow), both
   caught by live probes before they shipped. — **Prevention:** for every count or date the diff's
   prose adds, name the command that falsifies it and run it.

9. **Session-start gates all degraded:** `CLAUDE_PLUGIN_ROOT` was unset, so the readiness probe,
   cloud detection and `cleanup-merged` each reported `plugin-root-unverified` and skipped.
   — **Prevention:** the markers made the degradation legible, which is the design; no fix owed.

## Tags

category: machinery
module: post-mortems-and-cron-monitors
