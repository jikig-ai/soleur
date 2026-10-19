# Learning: a standing approval can only name PRs that exist, and the fix I was asked for was already merged

## Problem

Asked to "re-record the live delegation comment" and then to "open the next fix PR for #9757", two things turned out to be other than they looked.

1. A standing delegation (ADR-289) binds each Scope item to an existing pull request number and an exact command (`gh pr merge <N>`). Every PR the old record named was merged, and none of the remaining epic items had a PR yet, so there was nothing true to record. The founder's intent ("the CTO owns the epic and proceeds autonomously") cannot be expressed for PRs that do not exist.
2. The "next fix" (move the three heartbeat URLs off argv) was already on main (PRs #10086 and #10356). The umbrella checklist item was unticked only because its last status note was stale. The deliverable became an evidence-only closeout PR, confirmed by the operator in session.

## Solution

- Asked the operator what to record (they chose to wait for a PR to exist), then asked again once the PR question arrived (they chose the evidence-only closeout).
- Re-verified the premise on main before planning (content anchors, `git log`, the argv-bearer sweep: 823 passed, 0 failed) and shipped a knowledge-base-only PR with a scoped tick ("transport (argv)") deferred until after merge.
- Review (4 seats, report-only) found one P1 in my own evidence file: I wrote that `luks-monitor.sh` is delivered by an operator-applied root. It is installed by `terraform_data.luks_monitor_install`, which sits in the auto-applied SSH target list; only the heartbeat monitor and its URL secret are operator-applied. The claim had been inherited from a CTO ruling and a plan sentence and never falsified.

## Key Insight

A closeout PR is made of claims about other people's work, and each one is inherited from the plan, the ruling or the issue text. The ones about delivery paths ("X is applied by Y") are the ones to grep against the workflow's own target list before writing them down. Separately, a delegation record is a statement about acts that can already be named; an epic's future PRs need a different mechanism (a rolling re-record at PR creation, or a grammar that binds to a branch or label), which is a product gap, not an operator mistake.

## Session Errors

1. **Stale premise in the brief** — the requested conversion was already merged. Recovery: re-scoped to an evidence-only closeout after re-reading main and asking the operator. Prevention: the existing "re-read main before acting on a brief that names files as unconverted" rule held; no change.
2. **Lint exit code read through a pipe** — `markdownlint ... | tail -5; echo MDL_RC=$?` printed `tail`'s status (0) while the linter had reported errors in `session-state.md`; caught only because the output was read. Recovery: re-ran with the output redirected to a file and `rc=$?` on its own line. Prevention: already documented (`cmd | tail` takes the pipe's status); follow it for lints, not just test suites.
3. **A delivery-path claim inherited from a ruling and a plan, never falsified** — wrote "luks-monitor.sh is delivered through the operator-applied workspaces-luks.tf root" into the evidence file; the history seat refuted it with one grep of the apply workflow's `-target=` list. Recovery: corrected the evidence file, decision record and plan, and wrote the claim as "installer auto-applied; monitor and URL secret operator-applied; re-delivery not read". Prevention: for any "delivered by / applied by" sentence the diff adds, grep the apply workflow's target list and the operator-applied exclusions list before writing it.
4. **A scripted multi-edit asserted before writing** — the first plan-edit script failed an `assert` on a string I had retyped, so nothing was written (the correct failure direction); fixed and re-ran. Prevention: copy anchors from the file, not from memory; keep the assert-before-write shape.
5. **Stop hook rejected a closing sentence that promised an action** — "I'll open the PR ... and record a delegation" ended a turn with the action undone. Recovery: ended with a `Paused:` sentence naming the one thing awaited. Prevention: end turns on a result or a labelled `Paused:`/`Blocked:` sentence, never on a promise.
6. **A review seat wrote a file outside the scratchpad** (`git show ... > /tmp/none`). Prevention: brief report-only seats to read with `git show <sha>:<path>` to stdout and use the scratchpad for any file.

## Tags

category: workflow-patterns
module: soleur:go, soleur:one-shot, delegation-verify.sh
