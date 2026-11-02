---
title: "ci: machinery batch — affected-index red repair + completion schedule, merge-watch disarm fix, CMO-gate PR_NUM scoping, cla-timestamp permissions, main-health leg timeouts, push-red-rate root-cause"
date: 2026-11-02
slug: ci-machinery-batch-sweep
branch: feat-one-shot-11776-machinery-batch
issue: 11776
lane: cross-domain
---

# ci: machinery batch — seven open CI/machinery issues in one PR

## Overview

One PR disposes of the seven open CI/machinery items named in the #11796 ship
report: #11776, #10859, #11789, #11795, #3926, #9457, #9830. Three are code
fixes, two are code fixes with an investigation deliverable, one is a code fix
plus a scheduling artifact, and one is an explicit **operator hold** — nothing
in this PR flips a merge gate or multiplies per-PR CI spend. Per-item
disposition and acceptance criterion are in the table under Implementation
Phases.

Measured against `main` on 2026-11-02 while planning (all commands named inline
in Research Insights):

- `python3 -I scripts/ci-pr-affected-replay.py audit` →
  `gap_suites=279 gap_refs=1697` (issue #11776 quotes 272/1634 — main moved).
- `python3 -I scripts/ci-pr-affected-replay.py ratchet --report` →
  `exit=1 reason=new-pair live=1511 baseline=1510`: **the advisory
  `affected-index-ratchet` job is red on main right now**, one pair:
  `plugins/soleur/test/terraform-target-parity.test.ts` →
  `apps/web-platform/infra/inngest-userdata-budget.sh`. This red is what
  PAUSES the #10865 soak window that gates #10859 — repairing it is load-bearing
  for two of the seven items, not incidental.
- `GH_TOKEN=… bash scripts/followthroughs/ratchet-observation-window-10865.sh` →
  three `NOT YET` lines: latest merge_group unit red (`new-pair`), wall max 284 s
  over the provisional 270 s ceiling, and the read budget truncated the sweep.
  CTO ruling (2026-11-02, ratifies the ruling already on #10865): raise now —
  `P95_MAX=240`, `MAX_MAX=285` constants only; that two-constant diff lands in
  this PR (Phase 1).
- `gh run view 41305160049 --log` (cla-evidence-timestamp, 2026-11-01): the
  core succeeded — FreeTSA HTTP 200, `Verification: OK`, R2 upload — then
  `git push` died `403` (`permissions: contents: read` at
  `.github/workflows/cla-evidence-timestamp.yml:40`), and the `if: failure()`
  escalation step then ALSO failed on
  `could not add label: 'timestamp-failure' not found`. Two real defects.
- `gh run list --workflow main-health-monitor.yml`: 28 of the last 40 runs
  failed; the latest (41397335684) failed with legs **killed at their
  step ceilings** (`test-scripts` 15 min, `test-webplat` 10 min), one real
  `[FAIL] scripts/lint-orphan-test-suites-mutations-a`, and the monitor's own
  comment concludes "no failing suite confirmed — main's health is
  UNVERIFIED", which is a different signature from #9457's Oct-3
  `scripts/audit-suite-reads` red.
- `gh pr view <N> --json isInMergeQueue` → `Unknown JSON field` (gh 2.103.3):
  the queue flag is reachable ONLY via the GraphQL read that
  `sync-pr-behind.sh::queue_state_read` already owns — the #11789 fix must go
  through that reader, not `gh pr view`.

## Research Insights

### Premise Validation

All seven cited issues verified OPEN on 2026-11-02 via
`gh issue view <N> --json state,title` — none has a linked or open sibling PR
(parent collision preflight also ran clean). Cited artifacts verified present:
`.claude/hooks/ship-cmo-content-gate.sh` (the `PR_NUM` regex at the exact line
the issue quotes, scanning unstripped `$CMD`),
`plugins/soleur/scripts/monitor-pr-checks.sh` + `sync-pr-behind.sh` (the
armed/disarmed classification sites — the issue's "merge-watch" is not a file
name; the disarm-detection lives in `qw_snapshot`/`queue_wait_eval` and in the
monitor's `automerge` bit), `infra/github/ruleset-ci-required.tf`,
`scripts/required-checks.txt`, `scripts/pr-fanout-ledger.txt`,
`scripts/followthroughs/ratchet-observation-window-10865.sh`,
`.github/workflows/{ci,cla-evidence-timestamp,main-health-monitor}.yml`. What
was **stale**: the gap numbers (272/1634 → 279/1697), #3926's blocking
condition (Doppler creds now work — the failure moved to push permissions and
a missing label), and #9457's failure signature (the Oct-3
`audit-suite-reads` red no longer reproduces in the last 40 monitor runs; the
monitor's own newest comment reports a different, "did not complete" mode).
ADR corpus check (Phase 0.6 rule 4): ADR-276 + its PR3a amendment cover the
ratchet/required-context mechanism — #10859's mechanism is the
already-ADRed one, not a new one; ADR-270 covers the merge-queue semantics the
#11789 fix relies on.

### Property List (Phase 0.6b)

- P1: `affected-index-ratchet` reads `exit=0` on main again (the one red pair
  gets its runbook disposition).
- P2: the remaining index-completion work is recorded as an ordered,
  measurable schedule — not re-derived per session.
- P3: a queued PR never produces a "disarmed / needs re-arm" verdict from any
  watch surface (`autoMergeRequest=null` is only a disarm when
  `isInMergeQueue=false`).
- P4: `ship-cmo-content-gate.sh` resolves the PR number from the invocation
  the trigger regex matched, never from quoted command bodies.
- P5: `cla-evidence-timestamp.yml` completes end-to-end: push permitted,
  escalation path itself cannot fail on a missing label.
- P6: the main-health monitor completes a run instead of being killed at a leg
  ceiling, and its verdict distinguishes "red" from "unverified".
- P7: the push-vs-queue red-rate question (#9830) gets a documented
  classification and a tracked target, not a one-off answer.

### Cut List (Phase 0.6b)

- New "merge-watch" script — cut. The disarm-detection already lives in
  `sync-pr-behind.sh::queue_state_read`/`qw_snapshot` and
  `monitor-pr-checks.sh`; a new watcher buys no property (P3 is satisfied by
  gating the existing classification on the flag that same file already
  reads).
- A new scheduled workflow for the completion drain — cut. The slices already
  exist as issues (#10860, #10861, #10959); P2 is a schedule record, not new
  machinery.
- Required-context flip for `affected-index-ratchet` — cut from THIS PR (not
  cut from the roadmap): it is the held act in #10859, operator-class
  (money + merge-gate mutation) and two of its three entry conditions are
  measurably unmet today.
- A bespoke red-rate dashboard — cut. The main-health monitor already files
  its verdict issue; P7 is served by classifying the named window and adding
  the rate line to an existing report surface.

### Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on 2026-11-02 | Plan response |
|---|---|---|
| #11776: `gap_suites=272, gap_refs=1634` | 279/1697 measured (main grew) | Re-measure and publish the live numbers in the schedule artifact |
| #11776: "schedule the completion work" | Slice issues #10860/#10861/#10959 already exist and are OPEN | Schedule = ordered map of the remaining gap onto existing slices + named remainder; no new machinery |
| #11789: "the merge-watch poll loop" | No file named merge-watch; disarm-detection lives in `sync-pr-behind.sh` (`qw_snapshot`/`queue_wait_eval`, `--queue-wait` consumers) and `monitor-pr-checks.sh` (`automerge` bit + verdicts) | Fix the armed/disarmed classification at both producers; `gh pr view --json` cannot read `isInMergeQueue` (verified) so the fix routes through the existing GraphQL reader |
| #10859: entry conditions listed as preconditions | (1) #10865 still OPEN — probe says `NOT YET` on three counts incl. the red this PR repairs and a wall max over the PROVISIONAL ceiling; (2)(3) unverified | Operator hold — record measured evidence + hold; land no activation edit |
| #3926: "awaiting bootstrap re-run / Doppler creds" | Creds work; run 41305160049 proved `Verification: OK` + R2 upload; failed at `git push` 403 + missing `timestamp-failure` label | Code fix on workflow permissions + label bootstrap, then dispatch-verify |
| #9457: `audit-suite-reads` failure | Signature no longer present; current mode is legs killed at step timeouts + `lint-orphan-test-suites-mutations-a` FAIL | Investigation + leg-ceiling fix; keep issue as the monitor's living tracker |
| #9830: 8% red rate Oct 5–9 | Untouched since filing; queue-vs-push gap hypothesis unverified | Classification deliverable + target-rate line on the monitor's report |

### Institutional learnings consulted

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
  — the drain rubric (declared edge vs anchor-keyed accept row) for the red
  pair repair.
- `merge-queue-dequeue.md` + ADR-270 — queued-PR semantics the #11789 fix
  encodes.
- The #11796-ship-report convention (`fix(ci): cover uncovered affected-index
  pairs (#11814)`) — the same repair shape this plan repeats for the new pair.

### Open Code-Review Overlap

One open code-review issue touches a planned file: **#11312**
(`monitor-pr-checks.sh` — monitor_sig vs the per-PR lock). Disposition:
**acknowledge** — different concern (hook-layer residue), not folded in; it
stays open.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user artifact — every
  changed file is CI/agent machinery. Worst shapes: the merge-watch keeps
  emitting a false "disarmed", the CMO gate denies a legitimate `gh pr ready`
  (fail-closed, operator-visible), or the cla-evidence timestamp stays red.
- **If this leaks, the user's [data / workflow / money] is exposed via:** not
  applicable — no user-data surface; the cla-evidence workflow touches the CLA
  archive bucket with the same scoped R2 token it already uses.
- **Brand-survival threshold:** `none`
- *Scope-out:* `threshold: none, reason: CI/watchdog machinery and an internal
  PreToolUse hook — no user-facing path.`

## Implementation Phases

### Per-item disposition (the contract this PR must satisfy)

| Issue | Disposition | Concrete acceptance criterion |
|---|---|---|
| #11776 | Code fix (red-pair repair) + schedule artifact | `python3 -I scripts/ci-pr-affected-replay.py ratchet --report` exits 0 on this branch AND a schedule comment is posted to #11776 mapping the measured 279-suite/1697-ref remainder onto the existing slice issues (#10860, #10861, #10959) plus any uncovered remainder named explicitly |
| #10859 | **Operator hold (money + merge-gate authorization)** | A decision-challenges row + an issue comment recording: the hold, the measured soak evidence (`NOT YET` lines), the two unmet entry conditions (#10865 open; provisional ceiling needs the CTO re-rule the probe itself demands), and the exact activation edit set that stays un-landed. NO diff lands to `ci.yml` `continue-on-error`, `scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`, the count pin, or required-context fixtures for this issue |
| #11789 | Code fix | With `isInMergeQueue=true` and `autoMergeRequest=null` stubbed, no watch surface reports disarmed/needs-re-arm: `sync-pr-behind.sh --queue-wait` does not return `proceed` on that basis, and `monitor-pr-checks.sh` does not emit the not-armed verdict for a queued PR — new stub rows in `sync-pr-behind.test.sh` + `monitor-pr-checks.test.sh` prove both |
| #11795 | Code fix | A compound call `gh pr edit <N> --body '...gh pr merge <M>...' && gh pr ready <N>` resolves `PR_NUM=N`, not M — two new rows in `.claude/hooks/ship-cmo-content-gate.test.sh` (quoted-body before AND after the real invocation) |
| #3926 | Code fix + verification | `permissions:` grants `contents: write`; the escalation step bootstraps its labels (`gh label create … \|\| true` or existence check); after merge, a `workflow_dispatch` run lands `success` with `Verification: OK` and no `InvalidArgument` in the log |
| #9457 | Investigation + small fix | A findings comment on #9457 recording: the Oct-3 `audit-suite-reads` signature is resolved (absent from the last 40 monitor runs); the current mode is legs killed at step ceilings + one real suite fail (`lint-orphan-test-suites-mutations-a`); AND the leg-ceiling fix lands so a monitor run can complete |
| #9830 | Investigation + small fix | A cause-label table on #9830 classifying the 8 named push failures (flake / post-merge-only job / queue-miss) + the queue-vs-push gap documented + a stated target red rate tracked in the monitor's report surface |

### Phase 1 — affected-index repair + schedule (#11776)

1. Classify the red pair per the runbook rubric:
   `plugins/soleur/test/terraform-target-parity.test.ts:5876` holds
   `RUN_FULL = " run: bash apps/web-platform/infra/inngest-userdata-budget.sh --cap-only\n"`.
   Read the suite arm — if the fixture script is written into a scratch tree
   and the real file is never opened, it is a mention → anchor-keyed accept
   row in `scripts/ci-pr-affected-audit.accept.tsv`
   (`suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`); if
   the suite really executes it, declare the edge in
   `scripts/lib/test-affected-paths.sh`.
2. Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report` →
   must print `SOLEUR_PR_AFFECTED_RATCHET exit=0`.
3. Schedule artifact: `python3 -I scripts/ci-pr-affected-replay.py audit`
   numbers (279/1697) mapped onto the open slices; post to #11776 and add a
   short "completion schedule" note to
   `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
   pointing at the slice issues and the entry condition.

### Phase 2 — merge-watch disarm gating (#11789)

1. `plugins/soleur/scripts/sync-pr-behind.sh`: `qw_snapshot`'s armed bit is
   `autoMergeRequest == null → disarmed` with no queue consultation. Add the
   queue flag to the armed classification: when `autoMergeRequest` is null AND
   `isInMergeQueue` is true (read via the `queue_state_read` GraphQL answer the
   same file already owns — `gh pr view --json isInMergeQueue` does not exist,
   verified on gh 2.103.3), the PR must NOT classify `disarmed`; `--queue-wait`
   consumers (`step_guard`, the pre-merge hook's armed-BEHIND skip) then cannot
   read a queued PR as "proceed to sync" on a false disarm.
2. `plugins/soleur/scripts/monitor-pr-checks.sh`: gate the
   `automerge=false`-driven "not armed / needs re-arm" rendering and verdict
   paths on the queue read the script already performs (`in_queue` →
   `--queue-state`); a queued PR with `automerge=false` emits an annotated
   state (e.g. `automerge=false(queued)`), never the disarm verdict.
3. `plugins/soleur/skills/ship/references/ready-run-wait.md`: the
   "armed: `gh pr view … autoMergeRequest … not null`" probe needs the
   queued-PR caveat (a queued PR can read null — check `--queue-state` before
   concluding unarmed).

### Phase 3 — CMO gate PR_NUM scoping (#11795)

`.claude/hooks/ship-cmo-content-gate.sh`: extract `PR_NUM` from `$SCAN` (the
`strip_command_bodies`-scrubbed text already computed for the trigger test),
scoped to the invocation the trigger matched — take the PR number from the
`gh pr ready|merge` command at command position, never from quoted text; on
multiple real invocations take the last (the real action in a compound call).
Two regression rows in `.claude/hooks/ship-cmo-content-gate.test.sh`:
quoted-body containing `gh pr merge <M>` before and after the real
`gh pr ready <N>` — both must resolve `N`.

### Phase 4 — cla-evidence-timestamp permissions + label bootstrap (#3926)

`.github/workflows/cla-evidence-timestamp.yml`:

1. `permissions:` — add `contents: write` (the `git push -u origin "$branch"`
   at line ~282 died 403 under `contents: read`). `pull-requests: write` and
   `issues: write` already present.
2. Escalation step (`if: failure()`, line ~304): bootstrap
   `cla-evidence` and `timestamp-failure` labels before use —
   `gh label create <name> --force` or an existence check — so the
   dedupe/`gh issue create --label` path cannot itself fail. The step is the
   only operator-reaching channel on a monthly cron; its failure is silent.
3. Post-merge: `gh workflow run cla-evidence-timestamp.yml` (dispatch exists)
   then verify the run `success`, `Verification: OK`, no `InvalidArgument` —
   that green run is #3926's close condition.

### Phase 5 — main-health leg ceilings + red-rate classification (#9457, #9830)

1. #9457 findings: post the signature-drift comment (Oct-3 `audit-suite-reads`
   absent in last 40 runs; current mode = leg kills + one real suite fail).
2. `.github/workflows/main-health-monitor.yml`: the `Run test suite` steps
   carry `timeout-minutes: 10` (webplat leg) / 15 (scripts leg) ceilings that
   the current suite set measurably exceeds — the legs are killed mid-run and
   the monitor reports "unverified". CTO ruling (2026-11-02): realign by the
   workflow's own TIMEOUT BUDGET formula — `test-scripts` step 15→60 and job
   `timeout-minutes` 35→80; `test-webplat` step 10→30 and job 30→50;
   `test-bun` unchanged; no split (uncensored ci.yml run 41408788451 measured
   leg_max ≈37.6 min scripts / ≈17.2 min webplat; `leg_step =
   roundup5(leg_max × 1.5)`, `leg_job = leg_step + 20`). Keep
   `plugins/soleur/test/main-health-monitor-workflow.test.sh` green (it pins
   ceiling invariants).
3. `lint-orphan-test-suites-mutations-a`: file or fix the orphan suite it
   reports (the FAIL is a real defect, not monitor noise) — if it is a
   missing registration, register the suite per the orphan-lint contract.
4. #9830: classify the 8 push failures the issue names (2026-10-05→09 window,
   `gh run list --workflow ci.yml --branch main --event push` + per-run failed
   jobs) into flake / post-merge-only-job / queue-miss; document the
   queue-vs-push gap (jobs like `push-dedupe` run on push only and never gate
   the queue); state a target red rate and add the rate line to the
   main-health monitor's issue report template (the existing report surface —
   no new dashboard).

## Files to Edit

- `scripts/ci-pr-affected-audit.accept.tsv` *or* `scripts/lib/test-affected-paths.sh` (one row/edge, per Phase 1 step 1's rubric call)
- `scripts/followthroughs/ratchet-observation-window-10865.sh` (`P95_MAX=240`, `MAX_MAX=285` — CTO-ruled ceiling re-rule)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (schedule note)
- `plugins/soleur/scripts/sync-pr-behind.sh` (armed classification gains queue-flag input)
- `plugins/soleur/test/sync-pr-behind.test.sh` (queued+null-autoMergeRequest rows)
- `plugins/soleur/scripts/monitor-pr-checks.sh` (queued-annotated emission; disarm verdict gating)
- `plugins/soleur/test/monitor-pr-checks.test.sh` (queued+null-autoMergeRequest stub rows)
- `plugins/soleur/skills/ship/references/ready-run-wait.md` (armed-probe caveat)
- `.claude/hooks/ship-cmo-content-gate.sh` (PR_NUM from scrubbed `$SCAN`, invocation-scoped)
- `.claude/hooks/ship-cmo-content-gate.test.sh` (+2 quoted-body rows)
- `.github/workflows/cla-evidence-timestamp.yml` (`contents: write`; label bootstrap)
- `.github/workflows/main-health-monitor.yml` (leg step-ceiling realignment)
- `plugins/soleur/test/main-health-monitor-workflow.test.sh` (ceiling-invariant updates if pinned)
- The main-health monitor's issue-report template (red-rate line — wherever the report body is emitted; locate during work)

## Files to Create

- None required at plan time. (A followthrough script for #3926's
  dispatch-verify or #9457's monitor-completion check MAY be created at work
  time if the soak convention requires one; decide then per
  `followthrough-convention.md`.)

## Observability

```yaml
liveness_signal:
  what:            the affected-index-ratchet check conclusion per run (exit marker `SOLEUR_PR_AFFECTED_RATCHET exit=N reason=<kind>`), the main-health monitor's 6-hourly filed verdict, and the monthly cla-evidence-timestamp run conclusion
  cadence:         per-PR/per-queue-entry (ratchet), 6-hourly (monitor), monthly + dispatch (timestamp)
  alert_target:    PR check list; the monitor's living tracker issue (#9457); the timestamp workflow's auto-filed tracking issue
  configured_in:   .github/workflows/ci.yml, .github/workflows/main-health-monitor.yml, .github/workflows/cla-evidence-timestamp.yml
error_reporting:
  destination:     GHA job logs + step summaries + the monitor's filed issue comments
  fail_loud:       "`SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair`, monitor `[FAIL]`/`UNRESOLVED` lines, `::error::` in the timestamp job"
failure_modes:
  - mode:          a new uncovered suite→ref pair re-reddens the advisory
    detection:     ratchet job's own exit marker on the next pull_request/merge_group run
    alert_route:   the failing check + the #10865 soak probe's NOT YET line
  - mode:          a monitor leg is killed at its step ceiling again
    detection:     "health-check issue reports 'did not complete' with no confirmed failing suite"
    alert_route:   the living tracker issue comment
  - mode:          timestamp workflow's escalation path fails while reporting a failure
    detection:     run conclusion failure with no tracking issue filed (the Nov-1 shape)
    alert_route:   scheduled run red on the Actions list; the dispatch verify in Phase 4
logs:
  where:           GHA run logs (bounded retention) + step summaries
  retention:       GitHub default for workflow logs
discoverability_test:
  command:         bash -lc 'grep -q "contents: write" .github/workflows/cla-evidence-timestamp.yml && grep -q "isInMergeQueue" plugins/soleur/scripts/sync-pr-behind.sh && echo ok'
  expected_output: ok
```

## Guard Contract

The PR modifies two guard-class mechanisms (a PreToolUse gate and a watch
classification predicate); the ratchet repair is data, not a guard.

### Guard 1 — ship-cmo-content-gate PR_NUM resolution

**Property.** The gate evaluates the PR the `gh pr ready|merge` invocation at
command position names — never a number inside a quoted payload, so a compound
call can never deny or pass against the wrong PR.

**Assembly.** Every entry into the gate's PR resolution: the single `PR_NUM=`
line is the chokepoint — the trigger test (`grep -qE … gh\s+pr\s+(ready|merge)`
over `$SCAN`) and the resolution must read the same scrubbed text so a body
that slips the trigger cannot re-enter resolution.

**Mutation matrix.**

| Edit | Expected |
|---|---|
| Revert extraction to unstripped `$CMD` | RED — the quoted-body rows fail |
| Extract FIRST match instead of the command-position/last match | RED — a quoted `gh pr merge <M>` preceding `gh pr ready <N>` resolves M |
| Strip the trigger's own scrubbing (`SCAN` back to `$CMD`) | RED — a body mentioning `gh pr ready` fires the gate on a non-merge call |
| `strip_command_bodies` removed or made a no-op | RED — both quoted-body rows resolve the body's number |
| Test harness: delete the "quoted body AFTER invocation" row only | Suite must still RED on the "quoted body BEFORE" row — and the missing row itself is caught by the suite's row-count/conservation check (add one if none exists) |
| Must-PASS (non-canonical): `gh pr merge <N> --squash --auto` with a body-free invocation | PASS — resolves N |

### Guard 2 — merge-watch disarm classification

**Property.** "auto-merge disarmed" is asserted only when
`autoMergeRequest` is null AND `isInMergeQueue=false`; a queued PR can never
read as needing re-arm.

**Assembly.** Every consumer of the armed bit: `qw_snapshot` →
`queue_wait_eval` (`--queue-wait`, `step_guard`, `queue_wait_gate`) and
`monitor-pr-checks.sh`'s `automerge` emission + settled-block verdicts. The
chokepoint is the classification itself, not each consumer.

**Mutation matrix.**

| Edit | Expected |
|---|---|
| Classification reads `autoMergeRequest` only (drops the queue flag) | RED — queued+null stub reads disarmed |
| Queue flag checked but inverted (`isInMergeQueue=true` → disarmed) | RED — same stub proves the direction |
| `queue_state_read` failure collapsed into `disarmed` | RED — an unreadable queue read must not resolve to a disarm verdict |
| A second null-armed shape added after a compliant one (queued+null AND not-queued+null in one battery) | not-queued+null must still read disarmed; queued+null must not — both rows asserted |
| Must-PASS (non-canonical): `autoMergeRequest` non-null + `isInMergeQueue=false` | PASS — armed, unchanged behaviour |
| Harness row: stub `gh` to return malformed queue JSON | Suite asserts the read resolves `unknown`, not disarmed |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#11776 chore(ci): schedule affected-index completion — gap_suites=272, gap_refs=1634 (continues #10671, #10945, #11109, #11131, #11226)" [brief] | Phase 1 (ratchet repair + schedule artifact) | mapped |
| 2 | "#10859 ci: S4 PR3b, make the affected-index ratchet a required context. NOTE: the issue says \"held for the budget owner\" — a required-context flip multiplies per-PR CI spend. The plan must decide the correct vehicle: if the hold discharges only by operator budget authorization (money = operator-class), land the prerequisite code/config and record the flip itself as an explicit operator hold, never silently flip it." [brief] | Operator-hold disposition + evidence comment; no activation diff | mapped |
| 3 | "#11789 merge-watch: autoMergeRequest-null false-positive disarms merge-queue watches" [brief] | Phase 2 (queue-flag-gated armed classification) | mapped |
| 4 | "#11795 ship-cmo-content-gate: PR_NUM regex matches inside quoted command bodies — compound calls can deny against the wrong PR" [brief] | Phase 3 (SCAN-scoped extraction + 2 test rows) | mapped |
| 5 | "#3926 follow-through: verify cla-evidence-timestamp.yml first post-fix run lands green" [brief] | Phase 4 (permissions + label bootstrap + dispatch verify) | mapped |
| 6 | "#9457 CI: main-branch health check did not complete" [brief] | Phase 5.1–5.3 (signature findings + leg ceilings + orphan suite) | mapped |
| 7 | "#9830 ci: root-cause the 8% red rate on main despite the merge queue" [brief] | Phase 5.4 (classification + gap doc + target rate line) | mapped |
| 8 | "Investigation-heavy items (#9830, #9457, #3926) may resolve as findings+small fixes or verification-and-close. The plan must say PER ITEM whether it is a code fix, a verification-and-close, or an operator hold, and must give a concrete acceptance criterion per item." [brief] | Per-item disposition table above | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Ratchet red-pair repair | "chore(ci): schedule affected-index completion" / "#10865 … PAUSES … repair main first" (probe output) | inferred — justification: the live red blocks the #10865 window that gates #10859; an index issue cannot be scheduled against a red oracle |
| Schedule comment + runbook note | "schedule affected-index completion" | asked |
| Queue-flag-gated armed classification | "disarm-detect only when isInMergeQueue=false" [issue #11789] | asked |
| ready-run-wait.md prose caveat | "the watch records a false-positive disarm" [issue #11789] | inferred — justification: the reference text teaches the same wrong probe the fix removes |
| SCAN-scoped PR_NUM + test rows | "Parse only the invocation the trigger regex matched" [issue #11795] | asked |
| `contents: write` + label bootstrap | "verify cla-evidence-timestamp.yml first post-fix run lands green" [issue #3926] | inferred — justification: the post-fix run already ran and red'd on exactly these two defects; verification requires the fix first |
| Leg-ceiling realignment | "CI: main-branch health check did not complete" [issue #9457] | inferred — justification: measured cause of the current 'did not complete' mode |
| Orphan-suite disposition | "did not complete" run shows a real `[FAIL] lint-orphan-test-suites-mutations-a` | inferred — justification: a real suite failure inside the same surface the issue tracks |
| Red-rate classification + target line | "add the red rate to the main-health monitor" [issue #9830] | asked |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `.claude`, `.github` (+ `scripts`,
  `knowledge-base`, `infra/github` only via held/no-op notes: subsystem roots
  `scripts`, `knowledge-base`, `.claude`, `.github`, `plugins`, `infra` = 6 by
  the strict root count)
- Planned files: ~13 | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots fires on the strict count — but the work is
  seven small, independent fixes the brief explicitly requires in ONE PR;
  splitting would multiply CI cost for no isolation benefit (each fix is
  ~10–50 lines + tests)
- Recommendation: single PR (the threshold fires; the brief's "in ONE PR"
  instruction overrides, recorded here as the reason)

## Domain Review

**Domains relevant:** Engineering (CI infrastructure, internal tooling only)

Assessment (orchestrator inline — subagent spawn unavailable on this harness):
the change set is CI/agent machinery with no user-facing surface, no vendor
decision, no legal document, no marketing artifact, and no regulated-data
schema. Engineering is the implementing discipline, not a business-domain
consumer; Operations' assessment question (vendor/procurement/process spend)
touches #10859's CI-spend question, which is dispositioned as an operator
hold precisely because it is a budget authorization, not something a domain
leader can discharge in-plan.

### Engineering

**Status:** reviewed (orchestrator assessment — no domain-leader spawn available)
**Assessment:** All changes are local to existing CI/watchdog surfaces with
existing test harnesses; no new substrate, trust boundary, or architecture
decision. The required-context flip is held for operator authorization.

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Create/Edit (the mechanical
ui-surface-term scan returns zero hits). **Decision:** skipped (N/A).
**Pencil available:** N/A (no UI surface)

## Architecture Decision (ADR/C4)

None — no ownership/tenancy move, no new substrate, no resolver/trust-boundary
change, no ADR divergence. The required-context mechanism is already
ADR-276-amended; this plan changes no decision. A competent engineer reading
the existing ADRs + C4 after this ships would not be misled: the affected-index
machinery, merge queue, and health monitor are all already modeled.

## Encryption Posture

Skipped — no new persistent store, no new cross-component/network connection.
The timestamp workflow writes to the existing R2 bucket over the same TLS
endpoint it already uses.

## Task Design

Skipped — no new autonomous-task surface: no new `.github/workflows/*.yml`, no
new `schedule:`/`on:` trigger, no new Inngest function, no new host timer.
(`cla-evidence-timestamp.yml` already exists; its `schedule:` block is
untouched.)

## Acceptance Criteria

1. `python3 -I scripts/ci-pr-affected-replay.py ratchet --report` exits 0 on
   this branch (the `terraform-target-parity.test.ts` →
   `inngest-userdata-budget.sh` pair carries its rubric-correct disposition:
   declared edge in `test-affected-paths.sh` OR anchor-keyed accept row in
   `ci-pr-affected-audit.accept.tsv` with a `false-positive:` reason naming the
   line kind).
2. A schedule comment is posted to #11776 mapping the measured remainder
   (audit output on the merge head) onto #10860/#10861/#10959 and naming any
   uncovered remainder; `ci-pr-affected-activation.md` carries a pointer to it.
3. `bash plugins/soleur/test/sync-pr-behind.test.sh` and
   `bash plugins/soleur/test/monitor-pr-checks.test.sh` pass with the new
   queued+null-autoMergeRequest stub rows; a queued PR with
   `autoMergeRequest=null` never classifies `disarmed`.
4. `bash .claude/hooks/ship-cmo-content-gate.test.sh` passes incl. the two
   quoted-body compound-call rows resolving `PR_NUM` to the real invocation's
   number.
5. `.github/workflows/cla-evidence-timestamp.yml` carries `contents: write`
   and its escalation step creates `cla-evidence`/`timestamp-failure` labels
   before use; a post-merge `workflow_dispatch` run concludes `success` with
   `Verification: OK` and no `InvalidArgument` in the log (that green run is
   #3926's close condition).
6. `.github/workflows/main-health-monitor.yml` leg step ceilings cover the
   measured leg wall times (or the over-long leg is split); the next monitor
   run completes rather than being killed — verified on the next scheduled
   run or a dispatch, recorded on #9457 with the signature-drift findings.
7. #9830 carries the cause-label table for the 8 named failures, the
   queue-vs-push gap write-up, and the stated target red rate; the rate line
   is emitted by the monitor's report surface.
8. #10859 carries the hold comment (measured soak evidence, unmet entry
   conditions, exact un-landed edit set) and **no** activation diff lands: no
   `continue-on-error` deletion, no `required-checks.txt` row, no
   `ruleset-ci-required.tf` context, no count-pin change for
   `affected-index-ratchet` in this PR.
9. `bash scripts/test-all.sh --affected` (or the suites for the touched
   harnesses) is green locally before push; PR CI green including the
   `affected-index-ratchet` advisory job.

## Test Scenarios

- unit: `sync-pr-behind.test.sh` — stub `autoMergeRequest=null` +
  `isInMergeQueue=true` → `--queue-wait` never returns `proceed` on a disarm
  basis; `null` + `false` still reads disarmed (must-PASS row preserved).
- unit: `monitor-pr-checks.test.sh` — queued+null stub emits the queued
  annotation, never the not-armed verdict.
- unit: `ship-cmo-content-gate.test.sh` — quoted `gh pr merge <M>` inside
  `--body` before and after `gh pr ready <N>` → `PR_NUM=N` both times.
- unit: `main-health-monitor-workflow.test.sh` — ceiling-invariant pins still
  hold after the realignment (update pinned values if the suite asserts them).
- integration: `ci-pr-affected-replay.py ratchet --report` on the branch →
  `exit=0` (the live oracle check).
- e2e: post-merge `gh workflow run cla-evidence-timestamp.yml` → green;
  `pyramid-justified: the property is a live workflow+permissions+label
  interaction no local harness can reproduce.`

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Land #10859's activation edits in this PR anyway | The hold is operator-class (budget + merge-gate authorization) and two entry conditions are measurably unmet; silently flipping is the named failure mode |
| Drain a bounded slice of the 279-suite gap in this PR | "Schedule" is the ask; a slice drain is the slice issues' job (#10860/#10861/#10959) — folding it here hides the scheduling deliverable under partial work |
| New standalone merge-watch script | `queue_state_read` already owns the queue flag read; a second watcher buys nothing |
| `gh pr view --json isInMergeQueue` for the disarm gate | Field does not exist on gh 2.103.3 (verified) — GraphQL is the only read |
| Close #9457 as stale | The monitor still fails every run — just on a different signature; the tracker must carry the new mode or the next engineer re-opens the same hole |

## Deferrals & Operator Holds

- **#10859 activation flip** — operator hold (money + merge-gate
  authorization + unmet entry conditions). Already tracked by the issue;
  this PR posts the measured evidence comment. No new issue needed.
- **Full index completion (gap_suites=279)** — tracked by #10448 + slices
  #10860/#10861/#10959; this PR discharges only the scheduling ask (#11776).
- **CTO re-rule of the #10865 provisional wall ceilings** — recorded as a
  `pending` technical ruling in decision-challenges.md (subagent spawn
  unavailable): the probe measured max 284 s vs the 270 s provisional ceiling;
  default assumption: the ceiling is re-ruled upward against the measured
  series when #10865 is next evaluated, per the tracker's own re-rule clause.

## Sharp Edges (verification pass note)

Written against plan-sharp-edges.md at 2026-11-02 — the catalogue entries that
bite this plan's shape: (a) every AC above names a command or a verifiable
diff, not "verify it works"; (b) the #10859 hold is explicit — nothing in the
Files-to-Edit list performs the activation; (c) the merge-watch fix names the
chokepoint (`queue_state_read`/`qw_snapshot`/`queue_wait_eval`), not "the
watch"; (d) test-row counts are pinned per suite; (e) the
`discoverability_test.command` is a grep pair under the 15 s cap with a
literal `ok` expected output.
