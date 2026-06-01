# Learning: a silence/went-quiet detector must source its liveness signal from OUTSIDE the monitored system

## Problem

KB sync writes a `kb_sync_history` row only when a GitHub push webhook arrives and
a workspace matches (`workspace-reconcile-on-push.ts`). The **went-quiet** failure
class — an installed workspace whose pushes simply stop arriving — therefore writes
**zero** new rows. Its latest row stays `ok:true` forever, so it looks perfectly
healthy while its KB silently goes stale (the parent #4706 incident: a KB froze
~5 weeks, no error shown).

The naive fix is a time threshold on `kb_sync_history` ("no `ok:true` row in N
days"). It fails twice over: (1) the went-quiet system stops writing the very record
you'd query, and (2) it can't tell a *broken* repo from an *idle* repo (one that
legitimately has no commits) — so it either misses the freeze or floods the operator
with idle-repo false positives. NG3 of #4712 deferred the arm for exactly this
reason.

## Solution

Get the "did work actually arrive?" signal from an **independent** source the
monitored system cannot suppress. Here: GitHub's own `GET /repos/{owner}/{repo}`
→ `pushed_at`, read via the installation token, correlated against the workspace's
last `ok:true` sync. Fire only when **both** hold:

```
pushed_at > lastOkSyncAt + FRESHNESS_SLACK   AND   now − lastOkSyncAt > N days
```

The first clause (out-of-band push evidence) is what suppresses the idle-repo false
positive — no commits since the last sync ⇒ never fires. The second clause bounds
staleness. Use `pushed_at` (any-branch, one field, one call), not `GET /commits`
(paginated, bodies). Parse `{owner}/{repo}` from each workspace's own `repo_url`
(not shared constants that point at your own repo). Mint the token per-installation,
not per-workspace.

## Key Insight

**A monitor that reads only the monitored system's self-recorded history is blind to
silence, because going silent also stops the history.** Liveness/silence detection
needs a signal from a layer the failure cannot reach: the upstream producer (GitHub
`pushed_at`), the transport (webhook delivery log), or a separate heartbeat store.
This is the same shape as the cloud-task silence-watchdog (`cron-cloud-task-heartbeat.ts`),
which reads GitHub *issue* artifacts — not the task's own logs — to decide a task
went quiet. When you add a "detect X stopped happening" feature, ask first: *what
records X from outside X's own write path?* If the answer is "nothing," that
out-of-band signal is the actual feature to build.

Corollary (data-model): per-entity correlation needs a per-entity discriminator on
the row. `kb_sync_history` rows carry no `workspace_id`, so per-workspace
went-quiet had to scope its MVP to single-workspace owners (multi-workspace owners
skipped-and-counted; #4728 tracks the schema fix). When a row will later be queried
per-entity, give it the entity id at write time even if today's reader doesn't need it.

## Session Errors

None detected. Premise probe, worktree/draft-PR creation, focused CTO assessment,
and all commits ran clean on first attempt.

## Tags
category: integration-issues
module: kb-sync / observability
issues: 4717, 4706, 4712, 4728
