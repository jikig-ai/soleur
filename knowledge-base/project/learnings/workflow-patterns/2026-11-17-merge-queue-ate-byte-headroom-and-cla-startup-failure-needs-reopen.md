---
title: The merge queue ate my byte headroom, and a CLA startup_failure needs a close and reopen, not a re-run
category: workflow-patterns
date: 2026-11-17
module: ship / merge queue / CLA checks
related: [PR #12821, PR #12736, "#11789", "Ref #12008", "Ref #9421"]
---

# Learning: three merge-queue traps from PR #12821

PR #12821 (docs, merged `e6dd7d4b08` on 2026-11-16) hit three separate traps
between "ready" and "merged". Each one cost a cycle.

## Problem

### (a) A byte budget that passed on the PR failed in the merge queue

`scripts/lint-skill-body-budget.py` checks each lifecycle SKILL.md against its
ceiling in `plugins/soleur/test/skill-body-budget.json`. It reads the ceiling from
the merge base. On the PR, `postmerge/SKILL.md` fit under its 48000-byte ceiling.
While #12821 waited in the merge queue, #12736 landed on main and added 8 bytes to
the same file. The merge-group build combines main with the PR, so it measured
48006 bytes, over the 48000 ceiling, and the queue ejected the PR.

The PR's own check could not see this. It measured the PR head against an older
main. Only the queue build measures the real combination, and by then any
unrelated PR that touched the same file has already eaten the margin.

After #12821 merged, `postmerge/SKILL.md` is 47984 bytes: 16 bytes of headroom.
The next PR that adds prose to it will fail unless it trims something first.

### (b) CLA checks with `startup_failure` cannot be re-run

The `CLA Assistant` and `cla-evidence` checks run on `pull_request_target`. Both
can end with `startup_failure`, which means the runner never started. GitHub does
not allow a re-run of a `startup_failure` run.

The usual workaround, a PR comment such as `recheck`, re-fires the workflow, but
under `pull_request_target` the new run is attached to main's commit, not the PR's
head. The PR's required contexts stay missing, so the PR never enters the queue.

What works: close the PR and reopen it (`gh pr close N && gh pr reopen N`). This
fires the `reopened` event, and both checks run again on the same head SHA.

### (c) `autoMergeRequest` reads `null` while the PR is queued

While a PR waits in the merge queue, `gh pr view N --json autoMergeRequest` returns
`null`. A monitor that reads `null` as "auto-merge disarmed" will raise a false alarm
or re-arm a PR that is already queued. This is already written down in
`plugins/soleur/skills/ship/references/ready-run-wait.md` (caveat #11789). The
#12821 monitor was ad hoc and skipped that reference, so the trap fired again.

## Solution

- (a) Leave at least 50 bytes of headroom under any byte ceiling when you ready the
  PR. Measure `ceiling - wc -c` on the head you ready, not just pass or fail. If the
  margin is under 50 bytes, trim before you enqueue.
- (b) On a `startup_failure` from `CLA Assistant` or `cla-evidence`, close and reopen
  the PR. Do not comment, and do not try `gh run rerun`.
- (c) Read the queue state with
  `bash plugins/soleur/scripts/sync-pr-behind.sh N --queue-state`. `null` means
  disarmed only when the queue state is `not_queued` or `dequeued`.

## Key Insight

A check that passes on the PR is a check against yesterday's main. Anything with a
margin, like a byte ceiling, must keep enough slack to survive what lands on main
while the PR waits in the queue. And with `pull_request_target`, the commit a
re-fired check attaches to depends on the event that fired it, so pick the event
(`reopened`) that targets the PR's head.

## Session Errors

1. **Queue build failed on the skill-body budget (48006 > 48000) after an unrelated
   PR (#12736) added 8 bytes on main.** Recovery: trimmed and re-enqueued. —
   **Prevention:** keep at least 50 bytes of headroom at ready time (added to
   `plugins/soleur/skills/plan/references/plan-sharp-edges.md`, next to the existing
   measure-first bullet).
2. **`CLA Assistant` and `cla-evidence` ended in `startup_failure`; a re-run is not
   allowed, and a comment re-run attached the checks to main's commit.** Recovery:
   closed and reopened the PR, which re-fired both on the head. — **Prevention:**
   the remedy is now in `ship/references/ready-run-wait.md`, in the
   required-context section that already names `cla-evidence`.
3. **The merge monitor read `autoMergeRequest: null` on a queued PR as "disarmed".**
   Recovery: checked the queue state, which said queued. — **Prevention:** already
   documented (`ready-run-wait.md`, #11789). Ad hoc monitors must use the
   `--queue-state` probe and not read `autoMergeRequest` on its own.
4. **This session: `worktree-manager.sh --help` is not a command** (it printed usage
   after "Unknown command"). One-off, no impact. — **Prevention:** none needed; the
   usage text prints anyway.
5. **This session: the `durable-reminder-prefer-inngest` hook blocked a CronCreate
   reminder for #12820.** The Inngest path needs `INNGEST_MANUAL_TRIGGER_SECRET`, a prd
   secret, and the brief forbade reading live secrets. Recovery: re-sent with the
   hook's `gate-override` comment and the reason. — **Prevention:** when the brief
   forbids live-secret reads, take the override path on the first call and state why.
6. **This session: the PR body shipped the template placeholder "undo PR #N".**
   Recovery: replaced it with #12848 and ran `gh pr edit`. — **Prevention:** after
   `gh pr create` returns the number, grep the body for `#N` before moving on.

## Tags

category: workflow-patterns
module: ship, merge-queue, cla
