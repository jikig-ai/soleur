---
title: "`cd W && setsid A & setsid B` launches B in the original cwd — backgrounded suites ran the wrong tree twice"
date: 2026-10-30
category: workflow-patterns
tags: [bash, setsid, background-process, worktree, launch-bug]
symptoms: [backgrounded suite logs appeared then vanished from the worktree, ps showed `cd <bare-root>` in the child's argv, suites verified green against main instead of the branch]
module: Session
component: shell-launch
problem_type: workflow_issue
resolution_type: workflow_improvement
root_cause: operator_command_shape
severity: medium
issue: '#11562'
---

# `cd W && setsid A & setsid B` launches B in the original cwd

## Problem

On #11562 twice in one session, a launch line of the form

```bash
cd <worktree> && setsid nohup bash -c 'cmd A' ... & setsid nohup bash -c 'cmd B' ... &
```

put only command A in the worktree. `&` splits the line into jobs: `cd <worktree> && setsid A` is backgrounded **as one job**, while `setsid B` runs in the foreground shell whose cwd is still the launch directory (the bare repo root). B's inner `cd "$PWD"` then resolves to the bare root — silently.

Both times the consequence was suites executing `main`'s code: a stale pre-split `test-all-affected` arm run, and later three consumer suites (`test-all-infra-coverage-notice`, `ci-pr-selection`, `shard-totality`) whose green results verified nothing about the diff. ~40 min of compute plus a near-miss on "verified" results that were real but against the wrong tree.

## Diagnosis

- `ps -eo pid,etimes,args` showed the child's `bash -c` argv literally containing `cd /data/git-repositories/jikig-ai/soleur` — the bare root, not `.../.worktrees/<branch>`. The argv slot is the ground truth; inferring from where the log file landed is unreliable (the worktree log files existed early — created by the correctly-launched sibling — and later vanished under a battery hygiene sweep).
- The bare repo root accumulated `.work-run-*` strays; `git branch --show-current` there read `main`, confirming the wrong tree.

## Fix

Put the working directory inside the single-quoted `bash -c` string with a **literal path**, never `$PWD` evaluated in the launch shell, and never rely on a leading `cd` surviving a `&` split:

```bash
setsid nohup bash -c 'cd /abs/path/worktree && cmd > .log 2>&1; echo $? > .rc' </dev/null >/dev/null 2>&1 &
```

One `setsid` per backgrounded command is fine only when each carries its own literal-path `cd` inside its quoted string.

## Verification

After launch: `ps -eo args | grep '<suite-name>'` and read the `cd` argument in the child's argv — it must show the worktree, not the bare root. Also `ls <bare-root>/.work-run-*` should stay empty; strays there mean a launch escaped.

## Prevention

- The verifier-side rule that caught this: before crediting any suite verdict, confirm the run's cwd — `ps` argv `cd` slot or the log file's directory inside the worktree — matches the branch under test. A green suite on the wrong tree is worse than a red on the right one, because it looks like evidence.
- Sibling rule already observed: never interpret an `.rc` file without checking its mtime against the launch time — refused/stale runs leave old verdicts behind (`rc=4` read as live status for an hour).
