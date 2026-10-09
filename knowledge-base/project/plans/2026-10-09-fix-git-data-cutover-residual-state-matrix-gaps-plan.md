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
- A bounded retry around the timer start -> cut: needs a sleep seam the script (no test seam, ADR-214) does not have.

**Institutional learnings applied:**
`2026-10-03-a-failure-notice-must-tell-failed-from-unknown-and-the-census-must-run-the-body` (bodies are EXECUTED, not grepped; a new job output needs a reader — which is why none is added), `2026-09-15-my-access-gate-proved-a-different-argv...` (exit 0 with a warning over a failed recovery is a false green), `2026-10-02-mutating-before-the-impl-commit-makes-checkout-a-shredder` (commit the implementation before running mutants), `2026-09-28-a-retrying-unit...` (the `ci-deploy.test.sh` pin guards variable-unit timer-start forms in host scripts; this plan adds no timer-start line, and its suite is run once to confirm).

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

- `mode_unfreeze`: replace the warn-and-continue branch with `_store_refuse unfreeze-gc-timer gc_timer_restart_failed "$rc"` (exit 5), capturing the rc explicitly (`gd_exec … || rc=$?`). The sentinel is already cleared, so a re-run converges (absent sentinel -> `nothing_to_unfreeze` -> start attempted again).
- State the cost plainly in the runbook (not only in `decision-challenges.md`): in a flip the unfreeze step fails -> total unwind (flag off, redeploy, the finalizer's unfreeze retries the start and will usually fail the same way -> `RECOVERY_FAILED`); in a rollback the erasure probe is skipped and the finalizer retries; standalone `mode=unfreeze` goes red.
- Wording: the finalizer's two "unfreeze FAILED" error lines and the runbook `FREEZE_HELD` row gain "or the gc timer would not restart (`gc_timer_restart_failed`; the sentinel is already cleared and the same re-dispatch converges)", because the existing text says the sentinel may still block every store verb. The notify body is not changed.
- Runbook verdict map: add the `gc_timer_restart_failed` row (the RB suite requires every `_store_*` word to have one).

### Phase 3 — booting-host provision misread (item 5)

- `git-data-cutover.sh`: `refuse_if_store_unverified_or_not_empty` gains an optional `verified-only` argument that returns right after `_store_emit store-verified ok` (additive lines only; the count stage is skipped because a rollback after real use legitimately holds repositories). `mode_probe` sets `STORE_SOURCE="$LUKS_MAPPER"` (ADR-239 D1: the render serves only the mapper) and calls it after `access_gate`/`refuse_if_config_unsafe`, before the provision session. A booting or unbound host exits 5 as `store_unverified` (reason words as today) and a held sentinel as `cutover_frozen`, and no push or remove is attempted on an unverified store.
- Notify body (workflow L772): extend the one existing string so `PROBE_FAILED` reads "the probe step log names the verdict: `store_unverified` or `cutover_frozen` mean the host store was not verifiable and the push and remove were not attempted (re-verify with `mode=proof`); `residue_left` means a synthetic repository survived". The subject word stays `PROBE_FAILED`.
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
- `apps/web-platform/infra/git-data-cutover-access.test.sh` — MZ-U5/U6, MZ-P10/P11, FZ11/FZ12 (inside `case_fz`), a WF pin for the `touch` ordering, NB text row, mutants, restated `MUTANT_FLOOR` and `FLOOR`.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — notify-channel table, known-gaps sentences, verdict-map row.

## Files to Create

None (the specs `tasks.md` and, at ship, `decision-challenges.md` are pipeline artifacts).

## Open Code-Review Overlap

None. (Checked the open `code-review` issues against every file above.)

## Domain Review

**Domains relevant:** none

No cross-domain implications: runner-side CI/infra scripting behind a reviewer-gated workflow; no UI, copy, pricing or legal surface. The Art. 17 exposure in the issue's `User-Impact` line is unchanged (host wrappers untouched); its legal-ops half is #9153.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (dispatch-only workflow; no flip has been dispatched); the failure is owner-facing: a flip that fails to unwind the flag, or a notification that misnames the state, around the `/api/account/delete` erasure path.
- **If this leaks, the user's data is exposed via:** no new exposure vector: no credential binding, no new output, no host bytes in any notification, no new network edge.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change improves unwind and reporting accuracy of a workflow that needs a human-approved dispatch; host erasure behaviour is untouched, so a single-user tier (CPO sign-off) is not warranted.

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
    detection: finalizer flip arm keyed on flag_write_attempted; a failed flag-off write exports recovery_failed
    alert_route: notify-failure RECOVERY_FAILED issue and email
  - mode: gc timer will not restart after the sentinel is cleared
    detection: unfreeze step fails with verdict gc_timer_restart_failed
    alert_route: run goes red; the flip/rollback unwind or the notify FREEZE_HELD path reports it
  - mode: probe ran against an unverifiable (booting) store
    detection: probe step fails with verdict store_unverified or cutover_frozen before any provision call
    alert_route: notify PROBE_FAILED pointing at the verdict in the probe step log
logs:
  where: GitHub Actions run log of git-data-cutover.yml (script output lines "[git-data-cutover] STORE probe=... verdict=...")
  retention: GitHub Actions log retention for the repository
discoverability_test:
  command: grep -m1 -o gc_timer_restart_failed apps/web-platform/infra/git-data-cutover.sh
  expected_output: gc_timer_restart_failed
```

(The probe prints nothing until Phase 2 lands in this PR's tree; it is run once after the edit.)

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

- [ ] The `flag_write` step body touches `flag_write_attempted` after the xtrace guard and before the precheck script (a static pin plus a mutant that moves it after); executed finalizer: flip with `freeze_held` + `flag_write_attempted` (no `flag_written`) writes the flag off, redeploys and unfreezes (FZ11); rollback with only `flag_write_attempted` exits "nothing to unwind" without calling the host script (FZ12).
- [ ] `MODE=unfreeze` with the shim's timer-start rc set to 1 exits 5 with `unfreeze-gc-timer gc_timer_restart_failed` after the sentinel was cleared; the absent-sentinel arm does the same (MZ-U5/U6); a warn-only mutant goes RED.
- [ ] `MODE=probe` against an unverified store exits 5 `store_unverified` with NO provision session in the timeline; a foreign sentinel gives `cutover_frozen` (MZ-P10/P11); the happy path (MZ-P1) still passes with the extra read.
- [ ] Executed notify body keeps the subject word `PROBE_FAILED` and its text names `store_unverified`; no job output, no `needs.cutover.outputs` reference and no secret binding changed.
- [ ] `MUTANT_FLOOR` and `FLOOR` restated from a measured run; `git-data-cutover-access.test.sh`, `tests/scripts/test-git-data-root-token-census.sh`, the shell-trace credential-refusal lint and `ci-deploy.test.sh` pass; actionlint is clean on the workflow.
- [ ] Runbook: gc verdict-map row added; the booting-host `PROBE_FAILED` caveat replaced; the `FREEZE_HELD` row and the plain statement of the flip-unwind cost added; the `nothing_to_rollback` and force-cancel sentences kept.
- [ ] `git diff origin/main...HEAD -- .github/workflows/git-data-cutover.yml` touches none of the #9811 regions; the PR body's first line says merging alone does not mutate production; it uses `Refs #9439, #8211, #9066, #9377, #8609` only (no `Closes`); merged through the queue, no `--admin`.
- [ ] The rollback recipe (revert this PR) is simulated once in a scratch detached worktree: `git revert --no-commit` then the same targeted suite passes.

### Post-merge

- [ ] One comment on #9439 with the deferral table; the arm-B issue filed; #9439 not closed.

## Test Scenarios

- Given a flip whose flag write landed and whose read-back failed, when the run ends, then the finalizer writes the flag off, redeploys and unfreezes (executed finalizer, unit).
- Given a rollback that touched only the attempted marker, when the run ends, then the finalizer exits "nothing to unwind" and dials no host (unit).
- Given the gc timer start failing after the sentinel is cleared, when unfreeze runs, then it exits 5 with `gc_timer_restart_failed` (unit, ssh shim).
- Given a git-data host that is up but whose store marker is unbound, when `MODE=probe` runs, then verdict `store_unverified` and no provision call in the timeline (unit).
- Regression: every existing MZ, FZ, NB and Guard row stays green; a `mutate()` landed-edit assertion that stops matching is a signal, not noise.

## Risks and Sharp Edges

- **Taste decision for the owner (persisted to `specs/<branch>/decision-challenges.md`):** item 8 is fatal, so a gc timer hiccup after a proven flip triggers the total unwind (flag off plus a second web-1 restart) and the unwind's own retry will usually fail the same way. Alternatives: fatal for rollback and standalone unfreeze but red-without-unwind for flip; or an in-script retry (needs a sleep seam the script lacks). The plan takes fatal because it is the issue's literal ask and the smallest change; the cost is stated in the runbook.
- Item 6's marker over-approximates "a write landed"; the flag-off write it can trigger is idempotent, and the only pre-write refusals it could over-mark are gated earlier by the secrets and deny checks.
- Both exact floors (`MUTANT_FLOOR`, `FLOOR`) count by measured run, per measurement and not per loop iteration; rows added inside `case_fz` do not move `FLOOR`, new mutants do.
- The probe pre-flight is one more ssh session in `mode_probe`; the MZ-P timeline expectations change by exactly that read. `STORE_SOURCE="$LUKS_MAPPER"` there is an ADR-239 D1 coupling that MZ-P10/P11 pin.
- Commit the implementation before running mutants.
