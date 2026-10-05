# Merge-queue dequeue: detect and recover (#9454)

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 and [merge-pr/SKILL.md](../../merge-pr/SKILL.md) §5.2 when the poll prints `[ship.phase7.dequeued]` or a `[ship.phase7.sync_failed]` line for `kind=dequeued` (exit 13), or times out with the PR OPEN and not in the queue.

A red `merge_group` run does not fail the PR: it removes it from the queue (a `RemovedFromMergeQueueEvent` on the PR timeline, with a `reason`), leaving the PR `OPEN`. Measured 2026-10-05 (#9482): after a `failed_checks` removal auto-merge stayed armed and GitHub put the PR back at the end of the queue 2 to 3.5 minutes later (two PRs: 3m20s and 2m03s), with no `AutoMerge*` event in between. The one `manual` removal measured (#9477, a push) was not re-added by GitHub; it was re-armed explicitly 19 seconds later, so that is not proof auto-merge is cleared. Read `--queue-state` before pushing or re-arming (recipe steps 2 and 3). The PR head's checks stay green, because the failing run is on the queue's temp ref (`gh-readonly-queue/main/pr-<N>-<sha>`). A re-queued entry fails the same way unless its cause is fixed, so polling alone does not recover a deterministic failure.

A red **advisory** job (a `merge_group` job that is not in `scripts/required-checks.txt`, for example `lint-bot-statuses`) reddens the run but does not remove the PR. Do not push to a queued PR over it: the push removes the entry with `reason=manual` and costs a full re-queue (#9477: 15:11:45 enqueue, 15:13:46 manual removal, merged 16:07:56).

**Who sees it.** One read (`sync-pr-behind.sh <N> --queue-state`) says `dequeued` when the PR is `OPEN`, out of the queue, and either has a CURRENT removal event (newer than the last auto-merge re-arm and than the head commit, so a fixed-and-pushed or re-armed PR does not count) or was seen queued earlier (a marker the script leaves in the worktree's git dir). A confirming re-read follows a short nap, so the queue's own merge landing is never reported. A dequeue reached through the marker alone is reported ONCE: printing `dequeued` consumes the marker (as `--step` does on exit 13), so a PR you fixed and re-armed (CI running, not queued yet) reads `not_queued` afterwards, not `dequeued` again; a removal event is current only until the re-arm or the next push. Three callers use it:

- the Phase 7 fence, on every 5th OPEN tick of any `mergeStateStatus` (prints `[ship.phase7.dequeued]` and stops) and on the poll timeout (`Queue: …`), and `--step` on each BEHIND tick (`kind=dequeued rc=13`);
- `monitor-pr-checks.sh <N>` (drain-prs), which ends `LEFT THE MERGE QUEUE UNMERGED` on a `dequeued` read and never on an unreadable one;
- the pre-merge hook, which only skips the sync for a queued PR (a dequeued one is exactly the recipe's step 2).

A failed read is never a dequeue. Check by hand from the PR worktree:

```bash
N=<pr-number>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh" "$N" --queue-state   # <queued|not_queued|dequeued> <state> <armed|disarmed> removal=<reason|none>; a `dequeued` print consumes the marker, so read it once and act on it
```

`dequeued` (any `armed` value, `removal=` naming the reason) is a dequeue. `not_queued` with `removal=none` is not: it is not queued yet (including a PR you just re-armed), or a push dequeued it and it re-enqueues itself once green.

**Recover (agent-run, ONE re-enqueue):**

1. Read why: `gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith("gh-readonly-queue/main/pr-'"$N"'-"))'`, then `gh run view <databaseId> --log-failed` for the failing job. The limit is 100 because one queue entry runs about 8 workflows.
2. Before pushing, read `--queue-state`. `queued` means GitHub already re-queued the PR: a flake needs no push, and a push removes it from the queue again (`reason=manual`, a full re-queue). Push only a fix for a failure that will recur. Fix it on the PR branch. A conflict or lockfile / `kb-index` drift: `git merge origin/main` locally (merge-pr §3.1 "Route conflicts"), resolve, commit, push.
3. Re-arm once, only when `gh pr view "$N" --json autoMergeRequest --jq '.autoMergeRequest'` prints `null`: `gh pr merge "$N" --squash --auto`, then re-run the Phase 7 poll.
4. A second dequeue of the same PR: stop and report it to the operator with the failing run URL. Do not loop.

Never `gh pr update-branch`, push, or `--admin` a PR that is IN the queue. A push dequeues it, and `--admin` skips the `merge_group` verification the queue exists to run.
