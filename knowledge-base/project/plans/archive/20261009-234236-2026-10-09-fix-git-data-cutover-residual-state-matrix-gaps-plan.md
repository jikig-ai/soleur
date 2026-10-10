---
title: "git-data cutover: residual state-matrix gaps from the #8211 review"
date: 2026-10-09
slug: git-data-cutover-residual-state-matrix-gaps
branch: feat-one-shot-9439-git-data-cutover-state-matrix-gaps
issue: 9439
type: fix
priority: p3
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# git-data cutover: residual state-matrix gaps from the #8211 review

## Overview

Work the nine checklist items of #9439 against `.github/workflows/git-data-cutover.yml` and its
runner-side script. Take the three items that need neither a live host nor a new dispatch mode
(5, 6, 8); give item 1 a one-line mitigation; record the other five, plus the two "also open"
notes and one new finding, as an explicit deferral on #9439. The issue stays open (PR body uses
`Refs`).

Nothing here is dispatched, applied or rotated. Every change is runner-side (workflow YAML and
`git-data-cutover.sh`), exercised by one existing mutation-graded suite, plus runbook text. No
hash-bound host payload (`git-data-provision.sh`, `git-data-remove.sh`, `git-data-gc.sh`, the
transport wrapper, pre-receive) and no precheck script is edited. No infrastructure is
introduced, so the IaC routing gate does not apply. Merging this alone does not mutate production
(dispatch-only workflow, no Terraform file in the diff); the PR body's first line says so.

## Enhancement Summary

**Deepened on:** 2026-10-09
**Sections enhanced:** Research Insights, Implementation Phases 2-3, Acceptance Criteria, Risks
**Passes used:** plan-review panel (DHH, Kieran, code-simplicity, CTO devex), a state-matrix walk (spec-flow), a suite-pin enumeration, the sharp-edges catalogue, the mechanical halt gates (user-brand, observability, PAT, scope check)

### Key improvements

1. Item 6's marker moved from a new env var in the precheck script to one `touch` in the workflow step, mirroring `freeze_held`; the precheck script and its suite are no longer edited.
2. Item 5 lost its job-output plumbing: the verdict reaches the owner through reworded notify text (plain words only, since a backtick in that string is a command substitution) and the probe step log.
3. The probe pre-flight now reuses `refuse_if_unmounted` and `refuse_if_not_on_mapper` (an unmounted booting host reads `old_store_unmounted`, not `probe_failed rc=5`), refuses ANY sentinel (including the same-lineage one the proof tolerates) and is truncated to the store-verified facts so the entry count cannot time out the pre-flight.
4. Item 8 keeps one immediate no-sleep retry before failing, which removes the transient-ssh case from the flip-unwind trade-off.

### New considerations

- Test IDs MZ-U5/U6 already existed (now MZ-U7/U8/U9); RB requires each new `_store_*` word to be observed and have a row under the runbook's `## Verdict map`.
- A transient `flag_write_failed` that never landed now also runs the unwind (one unneeded web-1 restart); stated in the runbook.
- Flip resume arm B never unwinds the flag; filed as its own issue, not fixed here.

> **Superseded at review (2026-10-09).** The Phase 2 default below (a failed gc.timer restart exits 5 and a flip unwinds) was replaced
> by a CTO ruling after the review panel: the verb exits **6**, the probe and stamp key on "sentinel cleared", the finalizer never
> unwinds for a timer-only failure, and notify carries `GC_TIMER_STOPPED`. The `verified-only` pre-flight is also built from a named
> facts array and accepts only rc 0. The record is the ADR-239 amendment "2026-10-09 — the gc timer is not a cutover precondition" and
> `decision-challenges.md`. The sections below describe the pre-review plan and are kept as the dated record.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: nine gaps "each need host access or a new mode" | Three need neither: the unwind marker (6), the unfreeze timer restart (8) and the probe's booting-host misread (5) are runner-side. | Take 5, 6, 8. Defer the rest with a stated reason each. |
| Item 5: "`provision` failing on a booting host reads as `PROBE_FAILED`" | `git-data-provision.sh` exits 1 for every rejection (`reject()`), so the rc cannot discriminate; the reason is only on stderr. | A verified-only store pre-flight before the provision session gives the right verdict and keeps push/remove from running on an unverified store; the notify text points at the verdict word. No new job output. |
| Item 6: "dies between the flag write and its marker" | Real: `flag_written` is touched after the precheck script returns; a write that lands then fails its read-back (`flag_write_readback_failed`) exits before the touch, and the finalizer's flag-off arm is gated on that marker. | Mark BEFORE the script runs, in the workflow, exactly as the `freeze` step already does with `freeze_held` ("an over-eager marker is safe"). |
| Item 8: "only warns" | `mode_unfreeze` warns and returns 0 when the gc timer start fails (script lines ~787-793). | Fail the verb with its own verdict. |
| Parent: #9811 edits the same workflow | Its hunks sit at the Sentry precondition (~L238-250) and the Better Stack readback step (~L495-540). | Keep every edit outside those two regions. |

## Research Insights

**Premise validation.** #9439 open; #8211, #9153, #9066, #9811, #9878 open; PR #9440 merged (filed
the issue, does not close it). Cited script/workflow paths exist on this branch. The workflow has
run before (successful dispatches on record) but the runbook records the flip rehearsal as not yet
run. ADR corpus grep (`nothing_to_rollback`, gc timer, `PROBE_FAILED`, `flag_written`): only
ADR-239 (Amendment 2026-09-30) speaks to the area; it records that a failed probe "fails the run
red AFTER the unwind" and that the no-cleanup / no-standalone-probe gaps are tracked in the
deferred-items issue (this one). No mechanism proposed here sits in a rejected-alternatives table.

**Property List:**

1. A flip whose flag write may have landed always gets the flag-off unwind. (item 6)
2. A gc timer that will not restart after an unfreeze is a visible failure, not a warning. (item 8)
3. A probe that did not run its erasure steps because the store was unverifiable says so. (item 5)
4. A rollback that reports `nothing_to_rollback` does not imply the sentinel was checked. (item 1, mitigation only)

**Cut List** (considered and cut):

- New dispatch modes (`probe`, `sentinel`, `probe-cleanup`) -> items 1, 2, 3 -> cut: owner constraint "no new mode".
- A separate `workflow_run` notifier for force-cancel (item 4) -> cut: a new workflow, not validatable without a dispatch, widens the RESEND credential census (ADR-241).
- Extracting the Better Stack readback for a rollback finalizer readback (item 7) -> cut: it rewrites the region #9811 is editing.
- A script-side marker in `git-data-flag-precheck.sh` (env var, path validation, new verdict, four test rows) -> cut by plan review: the workflow's own `touch` before the script buys the same property in one line, and the only extra refusals it over-marks are ones the earlier secrets/deny gates already make unreachable.
- A `probe_verdict` job output, `PROBE_VERDICT` notify env, allowlist and re-pinned N-outputs/N-exprs -> cut by plan review: the verdict word is already in the probe step's annotation and log, and the notify body already points there; one reworded sentence carries it.
- A SLEPT retry around the timer start -> cut: needs a sleep seam the script (no test seam, ADR-214) lacks. An immediate, no-sleep single retry is kept (Phase 2) because it needs none.

**Institutional learnings applied:**
`2026-10-03-a-failure-notice-must-tell-failed-from-unknown-and-the-census-must-run-the-body` (bodies are EXECUTED, not grepped; a new job output needs a reader — which is why none is added), `2026-09-15-my-access-gate-proved-a-different-argv...` (exit 0 with a warning over a failed recovery is a false green), `2026-10-02-mutating-before-the-impl-commit-makes-checkout-a-shredder` (commit the implementation before running mutants), `2026-09-28-a-retrying-unit...` (the `ci-deploy.test.sh` pin guards variable-unit timer-start forms in host scripts; this plan adds no timer-start line, and its suite is run once to confirm).

### Deepen findings (suite and state-matrix verification)

Verified against the real files by a state-matrix walk, a pin enumeration and a correctness review:

- **No existing pin touches the edits.** The suite extracts only `finalizer.sh`, `notify_body.sh`, `teardown.sh`, `key_fetch.sh`, `ssh_config.sh` and `secrets_check.sh` (T:1969-1973); nothing pins the `flag_write` step body, the finalizer's `flag_written` literal, or the PROBE_FAILED string beyond NB6 (subject ends `PROBE_FAILED`, body has no `mode=unfreeze`, no `${{`). Keep `swords="$swords PROBE_FAILED"`.
- **Finalizer early exits.** L612 (`! flag_written && ! freeze_held`) is left unchanged: a flip always has `freeze_held` before the flag-write step can run (the step is gated on the freeze step's success), and rollback must keep ignoring the new marker. Only L625 changes; the header comment (~L572-577) and the L612-614 echo are reworded to name the marker.
- **RB suite.** Every `_store_*` word must be OBSERVED by a unit row and have a row under `## Verdict map` (runbook L902); the new `probe=unfreeze-gc-timer verdict=gc_timer_restart_failed` row goes next to the unfreeze rows (L964-968). `store_unverified`, `cutover_frozen`, `old_store_unmounted` and `store_not_on_mapper` are already observed words, so the probe changes add no RB word.
- **G5 census** requires exactly five `gd_capture` call sites; the plan adds none (it calls the existing `refuse_if_unmounted`/`refuse_if_not_on_mapper` helpers). **H5** requires the `mode_probe` calls to be plain statements (not in `$(…)`, `||`, `&&` or a pipe). **Verb census** scans `refuse_if_*` and `main`: no bare `touch`/`systemctl`/`rm` words there. The mutant `g2v-10` anchors on a literal line of the function; the plan keeps that line and does not rename the probe, so it still lands. `require_lineage` stays first in `mode_probe` (MZ-L).
- **Floors.** `MUTANT_FLOOR` (T:3197, exact, currently 115) moves +1 per new landed mutant; `FLOOR` (T:3211, exact, currently 549) moves +2 per landed mutant and +1 per new standalone MZ row (rows inside `case_fz` add none). Restate the comment blocks at T:3187-3210 from a measured run, not from this arithmetic. The shim already has `SHIM_GC_START_RC` (T:227); no shim edit.
- **Exit-status idiom.** Under `set -euo pipefail` capture with `local rc=0; gd_exec '…' || rc=$?`; a bare `gd_exec …; rc=$?` exits first.
- **Standalone `mode=unfreeze` after a timer failure** still exports `freeze_held=1` (FZ7 pins that); the notify remedy and runbook row would tell the owner to sweep Art. 17 refusals from the freeze start although the sentinel is gone. Hence the wording fix in Phase 2, not a finalizer behaviour change.

## Item disposition

| # | Checklist item | Disposition | Reason |
|---|---|---|---|
| 1 | `nothing_to_rollback` does not read a held sentinel | **Deferred** (mitigation taken) | The bridge/key/ssh_config steps are skipped on that path and a read-only sentinel verb is a new mode. Mitigation: the "Nothing to rollback" step states the sentinel was not read and names the recovery dispatch. |
| 2 | No finalizer cleanup of a failed/cancelled probe's synthetic repo | **Deferred** | Needs a remove-only verb (new mode); the probe already retries the remove once on a non-timeout failure. |
| 3 | No standalone probe mode | **Deferred** | A new dispatch mode. |
| 4 | Force-cancel / replaced pending run notifies nobody | **Deferred** | Platform behaviour; the mitigation is a new workflow with RESEND, not validatable without a dispatch. |
| 5 | `provision` on a booting host reads `PROBE_FAILED` | **Taken** | Phase 3. |
| 6 | Flag true with no unwind | **Taken** | Phase 1. |
| 7 | No per-host readback in the rollback finalizer | **Deferred** | Needs the Better Stack readback logic #9811 is rewriting; revisit after #9811 merges (shared extraction then). |
| 8 | Failed gc timer restart only warns | **Taken** | Phase 2. |
| 9 | Dead `mode=unfreeze` wiring for an Art. 17 re-drive (#9153) | **Deferred** | The re-drive is an app/legal-ops path, not this workflow. |
| - | Stale D6 rotate precondition; redeploy readback | **Deferred** | Not on the nine-item list; D6's recency bound is a design call next to #9811's Sentry hunk. Tracked by #9439. |

New finding (filed as its own issue at ship, not fixed here; the owner decides): **flip resume arm B never unwinds the flag.** `resume=arm_b` skips the flag write, so neither `flag_written` nor the new marker exists and a failed arm-B redeploy leaves the flag true. Touching the marker when `resume == arm_b` would fix it, at the price of changing what a failed resume does to the flag.

## Implementation Phases

Write the failing test row first in each phase (`cq-write-failing-tests-before`); commit the
implementation before running the mutant batteries.

### Phase 1 — unwind marker before the flag write (item 6)

- Workflow `flag_write` step (L460-464): after the existing xtrace guard and immediately before `bash apps/web-platform/infra/git-data-flag-precheck.sh`, add `touch "$RUNNER_TEMP/cutover-progress/flag_write_attempted"` with a comment mirroring the `freeze` step's ("marks that a write MAY have landed; the flag-off write is idempotent"). Keep the existing post-success `touch flag_written`.
- Finalizer (L625): the flip flag-off arm condition becomes `-f "$prog/flag_written" || -f "$prog/flag_write_attempted"`. The rollback conditions (L604, L612, L616) keep keying on `flag_written` only, so a rollback whose write failed still ends in "nothing to unwind" and never dials the host.
- Effect to document in the runbook verdict map: a flip whose flag write fails with a bad token now makes the unwind try the flag-off write with the same token, fail, and page RECOVERY_FAILED ("flag state unknown"). Noisy for a write that never landed, but truthful: the run cannot tell.

### Phase 2 — failed gc timer restart fails the unfreeze (item 8)

- `mode_unfreeze`: replace the warn-and-continue branch with `_store_refuse unfreeze-gc-timer gc_timer_restart_failed "$rc"` (exit 5), with `local rc=0` and `gd_exec 'systemctl start git-data-gc.timer' || gd_exec 'systemctl start git-data-gc.timer' || rc=$?` — one IMMEDIATE retry with no sleep (the start is idempotent and the likeliest cause is a transient ssh blip, 255 or 124, which would otherwise unwind a proven flip). The S:712 idiom: a bare `gd_exec …; rc=$?` exits first under `set -e`. The retry is a second ssh call; the timeline rows account for it. The sentinel is already cleared, so a re-run converges (absent sentinel -> `nothing_to_unfreeze` -> start attempted again).
- State the cost plainly in the runbook (not only in `decision-challenges.md`): in a flip the unfreeze step fails -> total unwind (flag off, redeploy, the finalizer's unfreeze retries the start and will usually fail the same way -> `RECOVERY_FAILED`); in a rollback the erasure probe is skipped and the finalizer retries; standalone `mode=unfreeze` goes red.
- Wording: the finalizer's two "unfreeze FAILED" error lines and the runbook `FREEZE_HELD` row gain "or the gc timer would not restart (`gc_timer_restart_failed`; the sentinel is already cleared and the same re-dispatch converges)", because the existing text says the sentinel may still block every store verb. The wording change for the notify body is in Phase 3 (plain words, no new output).
- Runbook verdict map: add the `gc_timer_restart_failed` row (the RB suite requires every `_store_*` word to have one).

### Phase 3 — booting-host provision misread (item 5)

- `git-data-cutover.sh`: `refuse_if_store_unverified_or_not_empty` gains an optional first argument read as `"${1:-}"` (`main()` calls it with none, and the script runs under `set -u`) that returns right after `_store_emit store-verified ok`. Additive lines only, and two details from review: (a) in the `rc 23` branch, before the same-lineage `ours` tolerance, add `[ "${1:-}" != verified-only ] || _store_refuse store-verified cutover_frozen`, so the probe pre-flight refuses ANY sentinel (the proof's resume-arm-A tolerance would otherwise pass it and let the host's `provision` refuse, the very misread being fixed); (b) when the argument is `verified-only`, the remote session is TRUNCATED to the store-verified facts: right after the array `c` is built (elements 0-9, through the marker-equals-UUID test) add `if [ "${1:-}" = verified-only ]; then c=("${c[@]:0:10}" 'echo 0'); fi`, so the repositories-directory and entry-count checks (rc 3, 4, 7, 8, 9, 96, and a `find` timeout on a large store) cannot fail or time out the pre-flight; a missing repositories directory then surfaces later as `probe_failed reason=provision`, stated in the runbook.
- `mode_probe` runs, after `access_gate`/`refuse_if_config_unsafe`: `refuse_if_unmounted`, `refuse_if_not_on_mapper`, then `refuse_if_store_unverified_or_not_empty verified-only` — the same order `proof` uses (S:848-852), instead of hard-assigning `STORE_SOURCE`. Reason: the pre-flight session opens with `findmnt … || exit 5`, so a host with no mount would read `probe_failed rc=5` and a wrong device `rc=6`; the two existing helpers name those states (`old_store_unmounted`, `store_not_on_mapper`), reuse existing capture sites (the G5 census still counts five) and set `STORE_SOURCE` from the real mount (ADR-239 D1). Result: a booting host reads `old_store_unmounted` or `store_unverified`, an unbound one `store_unverified`, a held sentinel `cutover_frozen`; no push or remove runs on an unverified store.
- Notify body (workflow L772, and the `FREEZE_HELD` words string at ~L770): the strings are inside a double-quoted shell string under `set -euo pipefail`, so the new text uses plain words only — NO backticks and NO `$` (a backtick is a command substitution: rc 127 would kill the one job that must not fail). `PROBE_FAILED` reads: "the probe step log names the verdict: old_store_unmounted, store_unverified, store_not_on_mapper or cutover_frozen mean the host store was not verifiable and the push and remove were not attempted (re-verify with mode=proof); residue_left means a synthetic repository survived". The `FREEZE_HELD` word gains "(sentinel still held, or the gc timer would not restart: the unfreeze step log names the verdict, and a mode=unfreeze re-dispatch converges)". Subject words stay `FREEZE_HELD` and `PROBE_FAILED`. No job output, no env, no allowlist. The executed NB row asserts the body step exits 0 and the text contains the verdict word.
- Runbook `PROBE_FAILED` row: replace the sentence "a `provision` failure while git-data is still booting reads as `PROBE_FAILED` too" with the verdict-word pointer.

### Phase 4 — item 1 mitigation, docs, deferral record

- "Nothing to rollback" step echo: add that the freeze sentinel was not read and that a stranded one is cleared by `mode=unfreeze` with `lineage=`.
- Header comment (workflow L37-39) and the runbook "When a cutover run fails" section: drop the sentences this PR makes false, keep the ones that stay true (`nothing_to_rollback`, force-cancel). Do not rewrite anything else.
- At ship time: post the deferral table as ONE comment on #9439 (including the D6 and redeploy-readback notes, which #9439 keeps tracking), and file the arm-B finding as its own issue (`type/chore`, `priority/p3-low`, `domain/engineering`, milestone "Post-MVP / Later", `Refs #9439`). Do not edit the issue body, do not close it.

## Conflict plan with PR #9811

Do not rebase onto, sync with or touch #9811. Edits stay clear of its hunks (the `flip_preconditions`
Sentry call and the "Per-host git_data_store= assertion" step). Mine land in: header comment,
"Nothing to rollback" step, `flag_write` step body, the finalizer, and one notify-body string. No
job `outputs:` or `needs.cutover.outputs` change, so the suite's N-outputs/N-exprs pins do not
overlap. If #9811 merges first, git merges separate hunks cleanly; on a textual conflict resolve
with the learning's recipe (save `git diff <merge-base> HEAD -- <file>`, check out main's copy,
`git apply --3way`), never `checkout --theirs`. After any sync, recount and re-measure
`MUTANT_FLOOR` and `FLOOR` before pushing, since both are exact literals a sibling can move.

## Files to Edit

- `.github/workflows/git-data-cutover.yml` — header comment, Nothing-to-rollback echo, `flag_write` step (`touch`), finalizer flip condition and two error lines, notify-body PROBE_FAILED string.
- `apps/web-platform/infra/git-data-cutover.sh` — `verified-only` argument, probe pre-flight, `mode_unfreeze` timer branch, header comment.
- `apps/web-platform/infra/git-data-cutover-access.test.sh` — MZ-U7/U8/U9 (U9: first start fails, retry succeeds, via a fail-once counter file in the ssh shim), MZ-P10/P11, FZ11/FZ12 (inside `case_fz`; FZ12 is a regression pin that passes before the change, so it is paired with a mutant adding `flag_write_attempted` to the L612 gate and expecting RED), a WF pin for the `touch` ordering, NB text row, mutants, restated `MUTANT_FLOOR` and `FLOOR`.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — notify-channel table, known-gaps sentences, verdict-map row.

## Files to Create

None (the specs `tasks.md` and, at ship, `decision-challenges.md` are pipeline artifacts).

## Open Code-Review Overlap

None. (Checked the open `code-review` issues against every file above.)

## Domain Review

**Domains relevant:** none

No cross-domain implications: runner-side CI/infra scripting behind a reviewer-gated workflow; no UI, copy, pricing or legal surface. The Art. 17 exposure in the issue's `User-Impact` line is unchanged (host wrappers untouched); its legal-ops half is #9153.

## User-Brand Impact

- **If this lands broken, the user experiences** (artifact -> vector; a future dispatch, not the merge): workspace owners' repository bytes and worktree writes when a flip's unwind runs against a writable store while the fleet still serves flag=true (writes accepted in the window, orphaned after flag-off); web-1 sessions during the unwind's both-host redeploy (a transient flag-write failure now also unwinds); Art. 17 refusals logged during an extended freeze; and the rollback's post-rollback erasure-probe evidence (the CPO condition on #8211) when an unfreeze step fails before the probe. The CTO ruling removes the first and last for a gc-timer fault; the probe/stamp-failure window is pre-existing and tracked.
- **If this leaks, the user's data is exposed via:** no new exposure vector: no credential binding, no host bytes in any notification, no new network edge; one new job output (`gc_timer_stopped`, a fixed word) carries no host data.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change improves unwind and reporting accuracy of a workflow that needs a human-approved dispatch. The host wrappers are untouched, but the erasure EVIDENCE path and the freeze duration are not (see above), which is why review ran the user-impact seat; the remaining exposure is a class (a failed late step after the sentinel clear), not an instance, so a single-user tier (CPO sign-off) is still not warranted.

## Observability

```yaml
liveness_signal:
  what: notify-failure job of git-data-cutover.yml (per-run; a failed, stranded or cancelled run files or updates the ci/git-data-cutover issue and emails ops)
  cadence: per-run
  alert_target: ci/git-data-cutover GitHub issue (primary) and the ops email (secondary)
  configured_in: .github/workflows/git-data-cutover.yml (job notify-failure)
error_reporting:
  destination: GitHub Actions annotations plus the ci/git-data-cutover issue; no Sentry (runner-side, no application runtime)
  fail_loud: "::error title=git-data-cutover store::probe=unfreeze-gc-timer verdict=gc_timer_restart_failed" and "probe=store-verified verdict=store_unverified" in the probe step; notify subject [git-data-cutover <mode> <result>] with the verdict words
failure_modes:
  - mode: flag write landed then read-back or the step failed (flag true, no marker)
    detection: layer 6 workflow run log: the finalizer prints "finalizer: writing GIT_DATA_STORE_ENABLED=false" (flip arm keyed on flag_write_attempted) and, on a failed write, "::error::finalizer: flag-off write FAILED"; exports recovery_failed
    alert_route: notify-failure RECOVERY_FAILED issue and email
  - mode: gc timer will not restart after the sentinel is cleared
    detection: layer 6 workflow run log: "::error title=git-data-cutover store::probe=unfreeze-gc-timer verdict=gc_timer_restart_failed rc=<n>" (unfreeze step exit 6); the finalizer exports gc_timer_stopped
    alert_route: run goes red and notify-failure sends GC_TIMER_STOPPED (no unwind, no freeze)
  - mode: probe ran against an unverifiable (booting) store
    detection: layer 6 workflow run log: "::error title=git-data-cutover store::probe=store-verified verdict=store_unverified" (or old_store_unmounted / store_not_on_mapper / cutover_frozen) in the probe step, before any provision call
    alert_route: notify PROBE_FAILED naming the verdict words and pointing at the probe step log
logs:
  where: GitHub Actions run log of git-data-cutover.yml (script output lines "[git-data-cutover] STORE probe=... verdict=...")
  retention: GitHub Actions log retention for the repository
discoverability_test:
  command: grep -m1 -o gc_timer_restart_failed apps/web-platform/infra/git-data-cutover.sh
  expected_output: gc_timer_restart_failed
```

(Presence-only: the grep proves the verdict word exists in source; the executed MZ/FZ/NB rows prove it surfaces. The probe prints nothing until Phase 2 lands in this PR's tree; it is run once after the edit.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A rollback that finds the flag already off (`nothing_to_rollback`) does not read a held freeze sentinel." [issue #9439] | Phase 4 mitigation + deferral row 1 | mapped (partial; remainder deferred, needs a new mode) |
| 2 | "No finalizer cleanup of the synthetic repository left by a failed or cancelled erasure probe." [issue #9439] | deferral row 2 | descoped — justification: needs a remove-only verb, a new mode (owner constraint) |
| 3 | "No standalone probe mode: a re-dispatched rollback exits `nothing_to_rollback`." [issue #9439] | deferral row 3 | descoped — justification: a new dispatch mode |
| 4 | "A force-cancel, or a pending run replaced in the `git-data-state` concurrency group, notifies nobody." [issue #9439] | deferral row 4 | descoped — justification: platform behaviour; a new notifier workflow cannot be validated without a dispatch |
| 5 | "`provision` failing on a booting host reads as `PROBE_FAILED`." [issue #9439] | Phase 3 | mapped |
| 6 | "`flip` dying between the flag write and its marker can leave the flag true with no unwind." [issue #9439] | Phase 1 | mapped |
| 7 | "Rollback has no per-host readback in the finalizer." [issue #9439] | deferral row 7 | descoped — justification: needs the readback logic #9811 is rewriting |
| 8 | "A failed `gc.timer` restart only warns." [issue #9439] | Phase 2 | mapped |
| 9 | "The dead `mode=unfreeze` wiring for an Art. 17 re-drive after a stranded freeze (see #9153)." [issue #9439] | deferral row 9 | descoped — justification: app/legal-ops path, tracked in #9153 |
| 10 | "taking each item that needs no host access or new mode and recording any that do as an explicit deferral on the issue" [brief] | Phase 4 deferral comment | mapped |
| 11 | "small, localized edits; do not rebase onto or touch #9811" [brief] | Conflict plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow `flag_write` touch + finalizer flip condition | asks 6 | asked |
| `mode_unfreeze` timer branch | asks 8 | asked |
| `verified-only` pre-flight in `mode_probe` | asks 5 | asked |
| Notify-body PROBE_FAILED string, runbook PROBE_FAILED row | asks 5 | asked |
| Finalizer error-line wording, runbook `FREEZE_HELD` row | asks 8 | inferred — justification: the existing text says the sentinel may still block store verbs, which is false for a cleared sentinel and a stopped timer |
| Test rows, mutants, restated floors | asks 5, 6, 8 | inferred — justification: the suite is exact-count mutation-graded; an unrestated floor reds CI |
| Runbook verdict-map row | asks 8 | inferred — justification: the RB suite requires a row per `_store_*` word |
| Header comment and runbook known-gap edits | asks 1, 5 | inferred — justification: they list gaps this PR makes false and would mislead |
| Arm-B issue (filed, not fixed) | asks 6 | inferred — justification: same outcome (flag true, no unwind) by a second path; filing it avoids silently widening failure semantics and avoids losing it in a comment |

### Split Assessment

- Subsystems touched: 3 — `.github`, `apps/web-platform`, `knowledge-base`
- Planned files: 4 | Estimated changed lines: ~250 (about 40 outside tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] The `flag_write` step body touches `flag_write_attempted` after the xtrace guard and before the precheck script (a static pin plus a mutant that moves it after); executed finalizer: flip with `freeze_held` + `flag_write_attempted` (no `flag_written`) writes the flag off, redeploys and unfreezes (FZ11); rollback with only `flag_write_attempted` exits "nothing to unwind" without calling the host script (FZ12).
- [x] `MODE=unfreeze` with the shim's timer-start rc set to 1 exits 5 with `unfreeze-gc-timer gc_timer_restart_failed` after the sentinel was cleared and after one immediate retry; the absent-sentinel arm does the same (MZ-U7/U8); a first-fail-then-succeed start exits 0 (MZ-U9); a warn-only mutant goes RED.
- [x] `MODE=probe` against an unverified store exits 5 `store_unverified` with NO provision session in the timeline; a foreign sentinel gives `cutover_frozen` (MZ-P10/P11); the happy path (MZ-P1) still passes with the extra read.
- [x] Executed notify body exits 0 with the new text (plain words, no backtick or `$`), keeps the subject words `PROBE_FAILED` and `FREEZE_HELD`, and its text names `store_unverified`; no job output, no `needs.cutover.outputs` reference and no secret binding changed.
- [x] `MUTANT_FLOOR` and `FLOOR` restated from a measured run; `git-data-cutover-access.test.sh`, `tests/scripts/test-git-data-root-token-census.sh`, the shell-trace credential-refusal lint and `ci-deploy.test.sh` pass; actionlint is clean on the workflow.
- [x] Runbook: gc verdict-map row added; the booting-host `PROBE_FAILED` caveat replaced; the `FREEZE_HELD` row and the plain statement of the flip-unwind cost added; the `nothing_to_rollback` and force-cancel sentences kept.
- [x] `git diff origin/main...HEAD -- .github/workflows/git-data-cutover.yml` touches none of the #9811 regions; the PR body's first line says merging alone does not mutate production; it uses `Refs #9439, #8211, #9066, #9377, #8609` only (no `Closes`); the merge route (queue, no `--admin`) is recorded by the merge commit.
- [x] The rollback recipe (revert this PR) is simulated once in a scratch detached worktree: `git revert --no-commit` then the same targeted suite passes.

### Post-merge

- [x] One comment on #9439 with the deferral table; the arm-B issue filed; #9439 not closed.

## Test Scenarios

- Given a flip whose flag write landed and whose read-back failed, when the run ends, then the finalizer writes the flag off, redeploys and unfreezes (executed finalizer, unit).
- Given a rollback that touched only the attempted marker, when the run ends, then the finalizer exits "nothing to unwind" and dials no host (unit).
- Given the gc timer start failing after the sentinel is cleared, when unfreeze runs, then it exits 5 with `gc_timer_restart_failed` (unit, ssh shim).
- Given a git-data host that is up but whose store marker is unbound, when `MODE=probe` runs, then verdict `store_unverified` and no provision call in the timeline (unit).
- Regression: every existing MZ, FZ, NB and Guard row stays green; a `mutate()` landed-edit assertion that stops matching is a signal, not noise.

## Risks and Sharp Edges

- **Taste decision for the owner (persisted to `specs/<branch>/decision-challenges.md`):** item 8 is fatal after one immediate retry, so a persistent gc timer failure after a proven flip triggers the total unwind (flag off plus a second web-1 restart) and the unwind's own retry will usually fail the same way. The retry removes the transient-ssh case. Alternative: fatal for rollback and standalone unfreeze but red-without-unwind for flip. The plan takes fatal because it is the issue's literal ask and the smallest change; the cost is stated in the runbook, including that a rollback with this failure also skips its erasure probe.
- Item 6's marker over-approximates "a write landed". The flag-off write it can trigger is idempotent, and the pre-write refusals are gated earlier by the secrets and deny checks, but a TRANSIENT `flag_write_failed` that never landed now also runs the unwind: flag off, a fleet redeploy (bounded at 900 s) and an unfreeze, i.e. one unneeded web-1 restart. Stated in the runbook; accepted because the run cannot tell a landed write from one that did not.
- Both exact floors (`MUTANT_FLOOR`, `FLOOR`) count by measured run, per measurement and not per loop iteration; rows added inside `case_fz` do not move `FLOOR`, new mutants do. Only the cutover-access suite is edited; the flag-precheck suite is not touched. The FZ pass message (T:2371 "11 … cases") is updated to the new case count. New case names are unique (`mz-u7-gcstart`, `mz-u8-gcstart-absent`, `mz-p10-…`, `mz-p11-…`): `run_case` writes `$T/<name>.out` and RB snapshots `$T/*.out`, so a reused name would overwrite an observed verdict.
- The probe pre-flight is one more ssh session in `mode_probe`; the MZ-P timeline expectations change by exactly that read. `STORE_SOURCE="$LUKS_MAPPER"` there is an ADR-239 D1 coupling that MZ-P10/P11 pin.
- Commit the implementation before running mutants.
