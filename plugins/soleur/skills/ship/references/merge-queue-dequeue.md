# Merge-queue dequeue: detect and recover (#9454)

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 and [merge-pr/SKILL.md](../../merge-pr/SKILL.md) §5.2 when the poll prints `[ship.phase7.dequeued]` or a `[ship.phase7.sync_failed]` line for `kind=dequeued` (exit 13), or times out with the PR OPEN and not in the queue.

A red `merge_group` run does not fail the PR: it removes it from the queue (a `RemovedFromMergeQueueEvent` on the PR timeline, with a `reason`), leaving the PR `OPEN`. Whether auto-merge stays armed after a removal is unmeasured (ADR-269 canary 3), so no check here depends on it. The PR head's checks stay green, because the failing run is on the queue's temp ref (`gh-readonly-queue/main/pr-<N>-<sha>`). Nothing re-arms it; polling longer cannot help.

**Who sees it.** One read (`sync-pr-behind.sh <N> --queue-state`) says `dequeued` when the PR is `OPEN`, out of the queue, and either has a CURRENT removal event (newer than the last auto-merge re-arm and than the head commit, so a fixed-and-pushed or re-armed PR does not count) or was seen queued earlier (a marker the script leaves in the worktree's git dir). A confirming re-read follows a short nap, so the queue's own merge landing is never reported. Three callers use it:

- the Phase 7 fence, on every 5th OPEN tick of any `mergeStateStatus` (prints `[ship.phase7.dequeued]` and stops) and on the poll timeout (`Queue: …`), and `--step` on each BEHIND tick (`kind=dequeued rc=13`);
- `monitor-pr-checks.sh <N>` (drain-prs), which ends `LEFT THE MERGE QUEUE UNMERGED` on a `dequeued` read and never on an unreadable one;
- the pre-merge hook, which only skips the sync for a queued PR (a dequeued one is exactly the recipe's step 2).

A failed read is never a dequeue. Check by hand from the PR worktree:

```bash
N=<pr-number>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh" "$N" --queue-state   # read-only: <queued|not_queued|dequeued> <state> <armed|disarmed> removal=<reason|none>
```

`dequeued` (any `armed` value, `removal=` naming the reason) is a dequeue. `not_queued` with `removal=none` is not: it is not queued yet, or a push dequeued it and it re-enqueues itself once green.

**Recover (agent-run, ONE re-enqueue):**

1. Read why: `gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith("gh-readonly-queue/main/pr-'"$N"'-"))'`, then `gh run view <databaseId> --log-failed` for the failing job. The limit is 100 because one queue entry runs about 8 workflows.
2. Fix it on the PR branch. A conflict or lockfile / `kb-index` drift: `git merge origin/main` locally (merge-pr §3.1 "Route conflicts"), resolve, commit, push.
3. Re-arm once: `gh pr merge "$N" --squash --auto`, then re-run the Phase 7 poll.
4. A second dequeue of the same PR: stop and report it to the operator with the failing run URL. Do not loop.

Never `gh pr update-branch`, push, or `--admin` a PR that is IN the queue. A push dequeues it, and `--admin` skips the `merge_group` verification the queue exists to run.
