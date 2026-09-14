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
rule_id: wg-when-a-test-runner-crashes-segfault-oom
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

- The first Phase 4 run printed `LOCK_WAIT_HEARTBEAT` every minute for 3600 s and then exited — no suite ran and no `LOCK_CONTENDED_PROCEEDING` line was written, although the lib's documented expiry behaviour is to proceed unserialized. `--capacity` showed the holder was a sibling worktree 96 minutes into its own battery with three more worktrees queued behind it.
- A Monitor task ended and the wrapper shell that launched the battery was SIGTERM'd; its `echo $? > rc` line wrote `143`. `ps` showed `bash scripts/test-all.sh` still alive under systemd with fd 1 on the same log.
- After the branch was pushed, `test-scripts (3/3)` failed AC17 (`INDEX.md` one file short of a fresh generation). Regenerating on the branch produced no diff.
- One of ten `secret-scan` smoke matrix jobs failed on `curl: (35) Recv failure: Connection reset by peer` downloading gitleaks.

## What Didn't Work

**Reading the wrapper's rc file as the run's verdict.** `143` was the wrapper's exit; the runner it had spawned survived the signal and kept going. Acting on the rc file would have relaunched a second battery beside a live one.

- **Why it failed:** the wrapper and the runner are two processes; a signal that reaches the parent does not reach a child in its own session, and the rc file only ever describes the parent.

**Regenerating the KB index on the branch head.** `generate-kb-index.sh` was clean because the branch's tree was consistent with itself.

- **Why it failed:** `pull_request` CI does not test the branch head. It tests `refs/pull/N/merge` — the head merged with *current* `origin/main` — and main had gained a KB file during the hour-long lock wait. GitHub's merge has no `kb-index` driver (`.gitattributes` registers one locally precisely because two sides adding the same number of files merge the `Total files` line cleanly and wrongly), so the drift lived in a tree that existed only on GitHub.

## Solution

1. Relaunch the battery with `TC_LOCK_TIMEOUT=10800` (and `setsid nohup`, so no harness task can reap the wrapper), then watch the **runner pid** with a `kill -0` + `/proc/<pid>/cwd` loop in a Monitor rather than the rc file. It acquired the lock after 23 minutes and ran 412/416 green (4 relevance-skipped). Two corrections from review: the wait is charged against `TC_RUNTIME_CEILING_S` (14400 s default), so a raised lock budget must raise the ceiling with it or a long queue leaves less execution time than a battery needs; and a bare `kill -0` has a pid-reuse hazard — anchor on the pid's cwd or starttime.
2. `git merge origin/main` again (which runs the local `kb-index` driver), regenerate `rule-metrics.json`, push. `test-scripts (3/3)` went green on the new head. `.claude/hooks/pre-merge-rebase.sh` performs that same merge + push on `gh pr merge`, so the red would also have self-healed at merge time; the manual step only shortens the window.
3. `gh run rerun <run> --failed` for the transient curl.

## Key Insight

Two different instruments reported on trees I never looked at. The rc file described a shell, not the runner it launched; CI described `refs/pull/N/merge`, not the head I had generated the index on. In both cases the fix was to read the thing that actually ran: the surviving pid, and a fresh merge of main. On a contended box the lock wait is the window in which main moves, so the sync with main has to be the last thing before the battery *and* re-verified after it.

## Session Errors

**1. The first Phase 4 battery never acquired the advisory lock.** Launched with `SOLEUR_ALLOW_FULL_GATE=1` (past the rc-4 sibling refusal) to queue inside the flock, against ship Phase 4's #8135 protocol of looping on `--capacity` until `measured_runs=0` and launching only then. `TC_LOCK_TIMEOUT` defaults to 3600 s, sized for a ~45-minute holder; with a 96-minute holder and four queued worktrees the budget expired by construction.

- **Recovery:** relaunched with `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=10800`; acquired after 23 minutes; green.
- **Prevention:** prefer the #8135 wait-outside-the-lock loop; when you deliberately queue inside it (`SOLEUR_ALLOW_FULL_GATE=1`) because `--capacity` lists two or more sibling runs, export `TC_LOCK_TIMEOUT` above the longest holder AND `TC_RUNTIME_CEILING_S=$((TC_LOCK_TIMEOUT + 10800))` before launching the Phase 4 battery — the default budget is shorter than a pile-up, and on expiry the lib proceeds unserialized beside the holder (contended evidence, the false-RED shape) rather than aborting.

**2. The wrapper's rc file recorded 143 while the runner lived on.** The launching shell was SIGTERM'd when a harness task ended; `bash scripts/test-all.sh` survived, reparented to systemd, and kept writing the same log.

- **Recovery:** verified via `/proc/<pid>/fd/1` that the survivor owned the log, then watched the pid (`while kill -0 <pid> && [[ "$(readlink /proc/<pid>/cwd)" == "$PWD" ]]; do sleep 15; done`) in a Monitor.
- **Prevention:** launch the battery with `setsid nohup … &` and record the runner's pid; treat an rc file as a verdict about the process that wrote it. rc=143 with a live child is not a run result — check `ps` before relaunching.

**3. AC17 KB-index drift on `refs/pull/N/merge`.** The branch head was self-consistent; the merge ref CI tests was one KB file richer because main moved during the lock wait.

- **Recovery:** merged `origin/main`, regenerated `rule-metrics.json` and the index, pushed; shard green.
- **Prevention:** CI tests the PR's merge ref, not the head, so "index is fresh on my branch" is not the property CI checks. An AC17-class failure with a clean local regeneration is the signature of a driver-less GitHub merge, not a broken branch — do not chase it on the head; a local `git merge origin/main` (the pre-merge hook does one on `gh pr merge`) runs the `kb-index` driver and fixes it.

**4. Transient `curl (35)` in one smoke matrix job** while downloading the gitleaks tarball.

- **Recovery:** `gh run rerun <run-id> --failed`; green.
- **Prevention:** one-off. Nine sibling jobs fetched the same URL successfully in the same run, so this is network, not the workflow; rerun before reading it as a regression.

## Related

- PR #8137 (the ship whose tail this is); pre-ship learning: `knowledge-base/project/learnings/security-issues/2026-09-14-the-plan-capped-the-message-before-it-redacted-it-and-a-config-is-not-a-consumer-boundary.md`
- `plugins/soleur/skills/work/SKILL.md` §9 "A long wait is legible rather than silent" (the heartbeat and the 3600 s budget)
- `plugins/soleur/skills/ship/SKILL.md` Phase 4 (battery) and Phase 6.4 (merge-main under lock)
- `knowledge-base/project/learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md` (ordinals surfaced by a fetch, never by a gate — the same "main moved while you waited" shape)
