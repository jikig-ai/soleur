---
module: Development Workflow
date: 2026-09-14
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "ship Phase 4 battery wrapper wrote rc=143 while a `bash scripts/test-all.sh` process with a `sleep 60` child kept writing LOCK_WAIT_HEARTBEAT lines to the same log for ~60 more minutes"
  - "that process exited at exactly the 3600 s lock budget with no LOCK_CONTENDED_PROCEEDING banner and no suite run"
  - "CI test-scripts (3/3) red on AC17 (INDEX.md Total files 6538 vs 6539) while generate-kb-index.sh was clean on the branch head"
  - "smoke (rename-guard-label-override) failed on curl (35) Connection reset by peer fetching gitleaks; 9 sibling matrix jobs green"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
rule_id: wg-when-a-test-runner-crashes-segfault-oom
tags: [ship, test-all, advisory-lock, heartbeat-subshell, pid-identity, refs-pull-merge, kb-index-driver, merge-tail]
synced_to: [ship]
---

# The runner I watched was its own heartbeat subshell, and CI tested a tree I had never built

## Problem

Shipping PR #8137 (retire the dead `SUPABASE_PAT`, #8028) on a box where four sibling worktrees were also running full batteries. The code was done and reviewed; the whole tail was spent misreading two instruments — a process that looked like the runner, and a CI verdict about a tree that existed only on GitHub.

## Environment

- Module: `scripts/test-all.sh` advisory lock (`scripts/lib/test-contention.sh`), `/ship` Phases 4 and 6.5, GitHub `pull_request` CI
- Affected Component: development workflow
- Date: 2026-09-14

## Symptoms

- The Phase 4 battery was launched with `SOLEUR_ALLOW_FULL_GATE=1` (past the rc-4 sibling refusal) and queued on the lock. About an hour in, the wrapper's `echo $? > rc` line wrote `143`. `ps` still showed `bash scripts/test-all.sh` — cwd this worktree, fd 1 on the same log, one `sleep 60` child — and the log kept receiving `LOCK_WAIT_HEARTBEAT` lines.
- That process exited at the 3600 s mark. Its last line was `waited=3541s`; no `LOCK_CONTENDED_PROCEEDING` banner was ever written and no suite ran.
- After the branch was pushed, `test-scripts (3/3)` failed AC17 (`INDEX.md` one file short of a fresh generation). Regenerating on the branch produced no diff.
- One of ten `secret-scan` smoke matrix jobs failed on `curl: (35) Recv failure: Connection reset by peer` downloading gitleaks.

## What Didn't Work

**Treating the rc file as a wrapper artefact and the look-alike process as the runner.** I concluded the wrapper had been reaped while its child lived on, and watched that pid instead of relaunching.

- **Why it failed:** `tc_acquire` forks `_tc_wait_heartbeat` as a background subshell. A forked subshell inherits argv, cwd and every fd, so `ps` and `/proc/<pid>/fd` cannot tell it from the runner. Its fingerprint is the one thing I did not check: a `sleep <interval>` child, and a self-terminate at `waited >= budget` — silent, exactly at 3600 s. A live runner would have printed `LOCK_CONTENDED_PROCEEDING` and run the battery unserialized. The rc file was telling the truth: the runner had received SIGTERM.

**Regenerating the KB index on the branch head.** `generate-kb-index.sh` was clean because the branch's tree was consistent with itself.

- **Why it failed:** `pull_request` CI tests `refs/pull/N/merge` — the head merged with *current* `origin/main` — and GitHub's merge has no `kb-index` driver. `.gitattributes` registers one locally precisely because two sides that add the same number of files merge the `Total files` line cleanly and wrongly. Main had gained a KB file during the hour-long wait, so the drift lived in a tree that existed only on GitHub.

## Solution

1. Relaunch under `setsid nohup … &` (the new session is what keeps a harness group-kill off the runner; `nohup` only ignores SIGHUP) and record the runner's **own** pid from `$!`. Watch that pid — `while kill -0 <pid> && [[ "$(readlink /proc/<pid>/cwd)" == "$PWD" ]]; do sleep 15; done` — never a process found by shape. The relaunch acquired the lock after 23 minutes and ran 412/416 green (4 relevance-skipped) with the default 3600 s budget.
2. `git merge origin/main` again (which runs the local `kb-index` driver), regenerate `rule-metrics.json`, push. `test-scripts (3/3)` went green on the new head. `.claude/hooks/pre-merge-rebase.sh` performs the same merge + push on `gh pr merge`, so the red would also have self-healed at merge time; the manual step only shortened the window.
3. `gh run rerun <run> --failed` for the transient curl.

## Key Insight

Two instruments each reported on something other than what I read them as. A process with the runner's argv, cwd and log was the runner's heartbeat child — identity is the pid you launched, not a shape you can match with `ps`. CI's red was about `refs/pull/N/merge`, a tree with a merge driver missing, not about the head I had regenerated on. In both cases the correct read was already written down nearby: `tc_acquire`'s expiry banner that never appeared, and the `.gitattributes` header explaining why the count merges wrongly.

## Session Errors

**1. The first Phase 4 battery was SIGTERM'd ~60 minutes into its lock wait and I read the rc=143 as a wrapper artefact.** A `bash scripts/test-all.sh` process was still alive, so I decided the wrapper had died and the runner survived. It was the orphaned `_tc_wait_heartbeat` subshell: same argv, `sleep 60` child, heartbeats to the same log, silent self-exit at the 3600 s budget, no `LOCK_CONTENDED_PROCEEDING`. What sent the SIGTERM is unresolved (the wait spanned a Monitor task's timeout); the runner was gone either way.

- **Recovery:** relaunched detached; watched the launched pid; green after a 23-minute queue.
- **Prevention:** identify the runner by the pid `$!` returned at launch, never by `ps`/`/proc` shape — a forked subshell is byte-identical on every axis except its children and its parent. A `bash scripts/test-all.sh` whose only child is `sleep <n>` and whose log shows heartbeats but no suites is the heartbeat, and an rc file the wrapper wrote is its verdict. If a run's log has heartbeats past the point the budget would expire with no `LOCK_CONTENDED_PROCEEDING`, the runner is dead.

**2. Raising `TC_LOCK_TIMEOUT` was the wrong remedy for that symptom, and would have needed `TC_RUNTIME_CEILING_S` raised with it.** I relaunched with `TC_LOCK_TIMEOUT=10800` on the theory the budget had expired; it acquired in 23 minutes, well inside the default. Review pointed out that expiry does not abort — it proceeds unserialized beside the holder (the false-RED shape) — and that the wait is charged against the 14400 s ceiling, so `10800` leaves 3600 s of execution, under the contended readings the lib records (3775–5787 s).

- **Recovery:** none needed; the ceiling was not reached.
- **Prevention:** prefer the #8135 wait-outside-the-lock loop. If you deliberately queue inside it (`SOLEUR_ALLOW_FULL_GATE=1`) on a pile-up, size `TC_LOCK_TIMEOUT` to the longest holder `--capacity` shows AND export `TC_RUNTIME_CEILING_S=$((TC_LOCK_TIMEOUT + 10800))`.

**3. AC17 KB-index drift on `refs/pull/N/merge`.** The branch head was self-consistent; the merge ref CI tests was one KB file richer because main moved during the wait and GitHub merged `INDEX.md` without the `kb-index` driver.

- **Recovery:** merged `origin/main`, regenerated `rule-metrics.json` and the index, pushed; shard green.
- **Prevention:** an AC17-class failure with a clean local regeneration is the signature of a driver-less GitHub merge, not a broken branch — do not chase it on the head; a local `git merge origin/main` (the pre-merge hook does one on `gh pr merge`) runs the driver and fixes it.

**4. Transient `curl (35)` in one smoke matrix job** while downloading the gitleaks tarball.

- **Recovery:** `gh run rerun <run-id> --failed`; green.
- **Prevention:** one-off. Nine sibling jobs fetched the same URL successfully in the same run, so this is network, not the workflow; rerun before reading it as a regression.

## Related

- PR #8137 (the ship whose tail this is); pre-ship learning: `knowledge-base/project/learnings/security-issues/2026-09-14-the-plan-capped-the-message-before-it-redacted-it-and-a-config-is-not-a-consumer-boundary.md`
- `plugins/soleur/skills/work/SKILL.md` §9 "A long wait is legible rather than silent" (the heartbeat and the 3600 s budget) and "A `ps | grep` hit is not YOUR process"
- `plugins/soleur/skills/ship/SKILL.md` Phase 4 (battery, the #8135 loop) and Phase 6.5 "Verify PR Mergeability" (#6536 `refs/pull/N/merge`)
- `.gitattributes` header (#7935) — why `INDEX.md` needs a three-way driver
- `knowledge-base/project/learnings/2026-09-03-three-checks-keyed-on-an-identifier-that-matched-more-than-i-meant.md` (a `pgrep -f`/shape match that includes more processes than the one you mean)
