# Merge-queue dequeue: detect and recover (#9454)

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 and [merge-pr/SKILL.md](../../merge-pr/SKILL.md) §5.2 when the poll prints a `[ship.phase7.sync_failed]` line for `kind=dequeued` (exit 13), or times out with the PR OPEN and not in the queue.

A red `merge_group` run does not fail the PR: it removes it from the queue and disarms auto-merge, leaving the PR `OPEN`. The PR head's checks stay green, because the failing run is on the queue's temp ref (`gh-readonly-queue/main/pr-<N>-<sha>`). Nothing re-arms it; polling longer cannot help.

**Who sees it.** `sync-pr-behind.sh` leaves a marker in the git dir the first time it reads the PR as queued. Its next read that finds the PR `OPEN`, out of the queue and auto-merge disarmed prints `kind=dequeued rc=13` and exits 13; the fence's `*)` arm stops the poll. The script runs only on a tick whose `mergeStateStatus` is `BEHIND` (a queued PR whose branch trails main is expected to stay BEHIND; ADR-269 canary 3 measures it), so a dequeued PR in any other state is seen only by the poll's timeout. Check by hand from the PR worktree:

```bash
N=<pr-number>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh" "$N" --queue-state   # read-only: queued|not_queued, state, auto-merge
```

For a PR you armed and saw queued, `OPEN`, `disarmed` and `not_queued` is a dequeue. `armed` and `not_queued` is not: a push dequeued it and it re-enqueues itself once green.

**Recover (agent-run, ONE re-enqueue):**

1. Read why: `gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith("gh-readonly-queue/main/pr-'"$N"'-"))'`, then `gh run view <databaseId> --log-failed` for the failing job. The limit is 100 because one queue entry runs about 8 workflows.
2. Fix it on the PR branch. A conflict or lockfile / `kb-index` drift: `git merge origin/main` locally (merge-pr §3.1 "Route conflicts"), resolve, commit, push.
3. Re-arm once: `gh pr merge "$N" --squash --auto`, then re-run the Phase 7 poll.
4. A second dequeue of the same PR: stop and report it to the operator with the failing run URL. Do not loop.

Never `gh pr update-branch`, push, or `--admin` a PR that is IN the queue. A push dequeues it, and `--admin` skips the `merge_group` verification the queue exists to run.
