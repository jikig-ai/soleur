---
module: Development Workflow
date: 2026-09-14
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "ship Phase 4 battery queued on the test-all advisory lock for the full TC_LOCK_TIMEOUT=3600s and exited without ever running a suite"
  - "the battery wrapper's rc file read 143 while the real scripts/test-all.sh child was alive, reparented to systemd, still writing the log"
  - "CI test-scripts (3/3) red on AC17 (INDEX.md Total files 6538 vs 6539) while generate-kb-index.sh was clean on the branch head"
  - "smoke (rename-guard-label-override) failed on curl (35) Connection reset by peer fetching gitleaks; 9 sibling matrix jobs green"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
rule_id: wg-after-a-pr-merges-to-main-verify-all
tags: [ship, test-all, advisory-lock, tc-lock-timeout, refs-pull-merge, kb-index-drift, monitor, merge-tail]
synced_to: [ship]
---

# The lock budget was shorter than the queue, and CI tested a tree I had never built

## Problem

Shipping PR #8137 (retire the dead `SUPABASE_PAT`, #8028) on a box where four sibling worktrees were also running full batteries. The code was done and reviewed; the whole tail was spent on the runner's queue and on a tree drift the branch head could not show.

## Environment

- Module: `scripts/test-all.sh` advisory lock (`scripts/lib/test-contention.sh`), `/ship` Phases 4 and 6.4, GitHub `pull_request` CI
- Affected Component: development workflow
- Date: 2026-09-14

## Symptoms

- The first Phase 4 run printed `LOCK_WAIT_HEARTBEAT` every minute for 3600 s and then exited — no suite ran. `--capacity` showed the holder was a sibling worktree 96 minutes into its own battery with three more worktrees queued behind it.
- A Monitor task ended and the wrapper shell that launched the battery was SIGTERM'd; its `echo $? > rc` line wrote `143`. `ps` showed `bash scripts/test-all.sh` still alive under systemd with fd 1 on the same log.
- After the branch was pushed, `test-scripts (3/3)` failed AC17 (`INDEX.md` one file short of a fresh generation). Regenerating on the branch produced no diff.
- One of ten `secret-scan` smoke matrix jobs failed on `curl: (35) Recv failure: Connection reset by peer` downloading gitleaks.

## What Didn't Work

**Reading the wrapper's rc file as the run's verdict.** `143` was the wrapper's exit; the runner it had spawned survived the signal and kept going. Acting on the rc file would have relaunched a second battery beside a live one.

- **Why it failed:** the wrapper and the runner are two processes; a signal that reaches the parent does not reach a child in its own session, and the rc file only ever describes the parent.

**Regenerating the KB index on the branch head.** `generate-kb-index.sh` was clean because the branch's tree was consistent with itself.

- **Why it failed:** `pull_request` CI does not test the branch head. It tests `refs/pull/N/merge` — the head merged with *current* `origin/main` — and main had gained a KB file during the hour-long lock wait. The drift lived in a tree that existed only on GitHub.

## Solution

1. Relaunch the battery with `TC_LOCK_TIMEOUT=10800` (and `setsid nohup`, so no harness task can reap the wrapper), then watch the **runner pid** with a `kill -0` loop in a Monitor rather than the rc file. It acquired the lock after 23 minutes and ran 412/416 green (4 relevance-skipped).
2. `git merge origin/main` again, regenerate `rule-metrics.json` + the KB index, push. `test-scripts (3/3)` went green on the new head. Do this **after** any long wait and re-check `mergeStateStatus` right before `gh pr ready` — `BEHIND` there is the tell.
3. `gh run rerun <run> --failed` for the transient curl.

## Key Insight

Two different instruments reported on trees I never looked at. The rc file described a shell, not the runner it launched; CI described `refs/pull/N/merge`, not the head I had generated the index on. In both cases the fix was to read the thing that actually ran: the surviving pid, and a fresh merge of main. On a contended box the lock wait is the window in which main moves, so the sync with main has to be the last thing before the battery *and* re-verified after it.

## Session Errors

**1. The first Phase 4 battery never acquired the advisory lock.** `TC_LOCK_TIMEOUT` defaults to 3600 s, which the runner docs say was sized for a ~45-minute holder; with a 96-minute holder and four queued worktrees the budget expired by construction.

- **Recovery:** relaunched with `TC_LOCK_TIMEOUT=10800`; acquired after 23 minutes; green.
- **Prevention:** when `bash scripts/test-all.sh --capacity` lists two or more sibling runs, export `TC_LOCK_TIMEOUT` above the default before launching the Phase 4 battery — the default budget is shorter than a pile-up, and a run that times out on the lock has produced no evidence at all.

**2. The wrapper's rc file recorded 143 while the runner lived on.** The launching shell was SIGTERM'd when a harness task ended; `bash scripts/test-all.sh` survived, reparented to systemd, and kept writing the same log.

- **Recovery:** verified via `/proc/<pid>/fd/1` that the survivor owned the log, then watched the pid (`while kill -0 <pid>; do sleep 15; done`) in a Monitor.
- **Prevention:** launch the battery with `setsid nohup … &` and record the runner's pid; treat an rc file as a verdict about the process that wrote it. rc=143 with a live child is not a run result — check `ps` before relaunching.

**3. AC17 KB-index drift on `refs/pull/N/merge`.** The branch head was self-consistent; the merge ref CI tests was one KB file richer because main moved during the lock wait.

- **Recovery:** merged `origin/main`, regenerated `rule-metrics.json` and the index, pushed; shard green.
- **Prevention:** CI tests the PR's merge ref, not the head, so "index is fresh on my branch" is not the property CI checks. After any long wait (lock queue, battery), merge `origin/main` again and re-check `gh pr view --json mergeStateStatus` for `BEHIND` immediately before `gh pr ready`; an AC17-class failure with a clean local regeneration is the signature.

**4. Transient `curl (35)` in one smoke matrix job** while downloading the gitleaks tarball.

- **Recovery:** `gh run rerun <run-id> --failed`; green.
- **Prevention:** one-off. Nine sibling jobs fetched the same URL successfully in the same run, so this is network, not the workflow; rerun before reading it as a regression.

## Related

- PR #8137 (the ship whose tail this is); pre-ship learning: `knowledge-base/project/learnings/security-issues/2026-09-14-the-plan-capped-the-message-before-it-redacted-it-and-a-config-is-not-a-consumer-boundary.md`
- `plugins/soleur/skills/work/SKILL.md` §9 "A long wait is legible rather than silent" (the heartbeat and the 3600 s budget)
- `plugins/soleur/skills/ship/SKILL.md` Phase 4 (battery) and Phase 6.4 (merge-main under lock)
- `knowledge-base/project/learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md` (ordinals surfaced by a fetch, never by a gate — the same "main moved while you waited" shape)
