---
title: The merge queue ate my byte headroom, and a CLA startup_failure needs a re-fired event, not a comment
category: workflow-patterns
date: 2026-11-17
module: ship, merge-queue, cla
related: [PR #12821, PR #12736, "#11789"]
---

# Learning: three merge-queue traps from PR #12821

PR #12821 (docs, merged `e6dd7d4b08` on 2026-11-16) hit three separate traps
between "ready" and "merged". Each one cost a cycle.

## Problem

### (a) A byte budget that passed on the PR failed in the merge queue

`scripts/lint-skill-body-budget.py` checks each lifecycle SKILL.md against its
ceiling in `plugins/soleur/test/skill-body-budget.json`, reading the ceiling from
the merge base. It runs in the `guards-ruleset` job of `ci.yml`, on both
`pull_request` and `merge_group`.

On the PR, `postmerge/SKILL.md` was 47998 bytes, 2 under its 48000 ceiling. The PR
check measures `refs/pull/N/merge`: the PR merged with main as of the last PR event.
While #12821 waited in the queue (enqueued 14:26Z), #12736 merged at 14:46Z and added
8 bytes to the same file. The merge-group build measured main as it was when the
PR's turn came, read 48006, and the queue ejected the PR at 16:26Z. Commit
`ff5134ae9f` trimmed it to 47984 and it was re-enqueued.

So the PR check is not wrong, it is stale: it measures against an older main. Only
the queue build sees what landed meanwhile.

`postmerge/SKILL.md` is now 47984 bytes: 16 bytes of headroom. Six of the ten
budgeted files on main are under 50 bytes spare (work 2, qa 11, plan 11, postmerge
16, one-shot 32, compound 40).

### (b) A comment does not re-fire a CLA check that hit `startup_failure`

The required contexts `cla-check` (workflow `CLA Assistant`, `cla.yml`) and
`cla-evidence` run on `pull_request_target`. At 16:29:20Z on head `4af860cf93` both
ended in `startup_failure`: zero jobs, `run_attempt` 1. Two other branches hit
`startup_failure` on the same workflows between 16:01Z and 16:44Z, and neither
workflow file had changed in weeks (`cla.yml` last on 2026-10-01, `cla-evidence.yml`
on 2026-09-07), so the cause looks GitHub-side and is undiagnosed. No re-run was attempted.

A PR comment re-fires the workflows on `issue_comment`, and those runs attach to
main's commit (`branch=main`, head `c02b95289e`), not the PR head. The PR's
required contexts stayed missing and it never entered the queue.

What worked: `gh pr close 12821 && gh pr reopen 12821` at 19:06Z. The `reopened`
event re-fired both `pull_request_target` workflows on the same head and both
passed. A sibling branch recovered the other way, with a new push (`synchronize`).

The reopen has costs that the first draft of this learning missed:

- The close turned auto-merge off (`auto_merge_disabled` at 19:06:45Z). It had to
  be re-armed by hand at 19:07:08Z.
- Closing fires `cleanup-unmerged-bot-branches.yml`, which deletes the head branch
  for `ci/`, `bot-fix`, `learning-`, `review-` and `soleur/inngest-pin-` prefixes
  without checking for a reopen. #12821's branch did not match; one of the other
  `startup_failure` branches (`ci/campaign-calendar-…`) would have.
- `reopened` re-runs every PR workflow, including `ci.yml` and the paid Claude
  review, so a re-fire during an ongoing GitHub incident is not free to repeat.
- `dev-ledger-reconcile.yml` also fires on the close; it re-checks the PR state
  inside its lock and skips once the PR is reopened.

### (c) `autoMergeRequest` reads `null` while the PR is queued

While a PR waits in the merge queue, `gh pr view N --json autoMergeRequest` returns
`null`. A monitor that reads `null` as "auto-merge disarmed" raises a false alarm or
re-arms a PR that is already queued. This is already written down: the #11789
caveat in `plugins/soleur/skills/ship/references/ready-run-wait.md`, and
`2026-10-07-merge-queue-silent-ejection-re-enqueue.md` in this directory. The
#12821 monitor was an ad hoc loop that skipped both, so the trap fired again.

## Solution

- (a) For each budgeted SKILL.md your diff grows, leave at least 50 bytes under its
  ceiling, measured as `ceiling - wc -c` on the head you ready. A file already under
  50 needs a trim of its shortfall plus your growth. 50 bytes absorbs a small edit
  like #12736's 8; it does not absorb a large one (`postmerge/SKILL.md` has taken
  +138 and +287 in single PRs), so re-measure after merging main. Added to
  `plugins/soleur/skills/plan/references/plan-sharp-edges.md` (plan time) and to
  the local gate list in `ready-run-wait.md` (ready time).
- (b) On a `startup_failure` of `cla-check` or `cla-evidence`, do not comment.
  Detect it by workflow path, re-fire once, and report if it fails again. If the
  PR is behind main, `gh pr update-branch` (a merge commit passes the arm check
  without a new review). Otherwise, on a branch without a bot prefix, close and
  reopen and re-arm. On a bot-prefixed branch, push an empty commit and re-review.
  Added to `ready-run-wait.md` as its own bullet keyed on the context name, not on
  one RECOVERY line: when a CI run at the head was cancelled (readying a draft
  cancels the in-flight run), `ci-head-verdict.sh required` prints the candidate
  lines, not `no cancelled run`.
- (c) Use the Phase 7 poll or `plugins/soleur/scripts/monitor-pr-checks.sh`, not an
  ad hoc loop. Both read the queue state; the full rules (including `dequeued` and
  exit 4) are in `ready-run-wait.md`.

## Key Insight

A check that passes on the PR is a check against an older main. Anything with a
margin, like a byte ceiling, needs enough slack to survive what lands on main while
the PR waits. And for a `pull_request_target` check, the commit a re-fired run
attaches to depends on the event that fired it: `issue_comment` goes to main,
`reopened` and `synchronize` go to the PR head. Before prescribing a re-fire, list
what else that event triggers.

## Session Errors

1. **Queue build failed on the skill-body budget (48006 > 48000) after an unrelated
   PR (#12736) added 8 bytes on main.** Recovery: trimmed in `ff5134ae9f` and
   re-enqueued. — **Prevention:** the 50-byte rule above, in
   `plugins/soleur/skills/plan/references/plan-sharp-edges.md` and
   `plugins/soleur/skills/ship/references/ready-run-wait.md`.
2. **`cla-check` and `cla-evidence` ended in `startup_failure`; a comment re-run
   attached the checks to main's commit.** Recovery: closed and reopened the PR,
   then re-armed auto-merge. — **Prevention:** the remedy (detection read, retry
   cap, branch-prefix guard, re-arm) is a `ready-run-wait.md` bullet keyed on the
   absent context, so it is reached whichever RECOVERY line the resolver prints.
3. **The merge monitor read `autoMergeRequest: null` on a queued PR as "disarmed".**
   Recovery: checked the queue state, which said queued. — **Prevention:** monitor
   with the Phase 7 poll or `monitor-pr-checks.sh`, never an ad hoc loop.
4. **This session: `worktree-manager.sh --help` is not a command** (it printed usage
   after "Unknown command"). One-off, no impact. — **Prevention:** none needed.
5. **This session: the `durable-reminder-prefer-inngest` hook blocked a CronCreate
   reminder for #12820.** The Inngest path needs a prd secret the brief forbade
   reading, so the reminder was re-sent with the hook's `gate-override`. —
   **Prevention:** use the override only for a reminder that fires within this
   session; for anything later, leave a dated comment on the issue and say the
   session cron will not survive the session.
6. **This session: the PR body shipped the template placeholder "undo PR #N".**
   Recovery: replaced it with #12848 and ran `gh pr edit`. — **Prevention:** after
   `gh pr create` returns the number, grep the body for `#N` before moving on.
7. **This session: the first draft of the close-and-reopen remedy omitted the
   auto-merge re-arm and the branch-deleting `closed` workflow, and the second draft
   hung it on a RECOVERY line the resolver often does not print.** Found by review.
   — **Prevention:** before prescribing a GitHub event as a remedy, grep
   `.github/workflows/` for every workflow that event (and its inverse, here
   `closed`) triggers.

## Related

- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`
  — a different `startup_failure` cause (a workflow-file limit, zero jobs).

## Tags

category: workflow-patterns
module: ship, merge-queue, cla
