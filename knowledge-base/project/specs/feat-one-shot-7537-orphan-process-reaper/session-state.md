# Session state — #7537 orphan process reaper

Written 2026-08-20. Branch `feat-one-shot-7537-orphan-process-reaper`,
worktree `.worktrees/feat-one-shot-7537-orphan-process-reaper`, draft PR 7641, closes #7537.

## Position in the pipeline

`/one-shot` Steps 0b/0c complete. **Steps 1-2 (plan + deepen-plan) did NOT finish.**
Nothing of the feature is implemented. Two commits exist: `chore: initialize` and the plan
checkpoint. Do not treat the pushed branch as progress on the feature.

## Why it halted

An MCP reconnect dropped the entire `soleur` plugin registry — every skill and all ~70
`soleur:*` agents — mid-run. Confirmed process-wide (a fresh subagent saw the same empty
registry). The plugin is intact on disk and enabled in settings; a CLI restart restores it.
Filed as issue 7645. The run halted rather than hand-rolling the pipeline, because
improvising the child skills is exactly what one-shot's anti-bypass protocol forbids.

## The plan artifact is a deliberate partial

`knowledge-base/project/plans/2026-08-20-feat-orphan-process-reaper-deleted-cwd-conjunction-plan.md`
has correct frontmatter (`branch:`, `issue: 7537`), an `## Overview`, and **no
`## Acceptance Criteria`**. That absence is the predicate one-shot's plan-artifact-recovery
block branches on, and it correctly reads as "planning did not finish". Continue that file in
place — do not start a second plan file.

## Environment hazard

`git commit` hangs forever on this box: `commit.gpgsign=true` + `gpg.format=ssh` routes to
GNOME Keyring's agent (`SSH_AUTH_SOCK=/run/user/1001/gcr/ssh`), which raises a GUI passphrase
prompt nothing can answer. `ssh-add -l` returns 0 in this state, so it is useless as a check.
Workaround: `git -c commit.gpgsign=false commit`. Filed as issue 7644. Nine commits from other
sessions were wedged when this was written — **do not kill them**, they are other sessions'
in-flight work.

## Collision gate — already resolved, do not re-litigate

PR 7538 surfaced in both the `linked:issue` and body-text probe sets and shares
`scripts/test-all.sh` with #7537's body. It is a **citation, not a collision**: 7538 closes
three sibling issues from the same incident class, never touches `scripts/tmpfs-guard.sh`, and
the path overlap traces to #7537 enumerating its siblings ("one of four items in that class").

Separately: `apps/web-platform/infra/orphan-reaper.sh` already exists on main. It is a 33-line
reaper for stale `.orphaned-*` workspace **directories** on the prod web host — a pure name
collision. Do not reuse that name; pick one that says "process".

## Binding constraints (from the issue body — read it with `gh issue view 7537`)

- Detector keys on deleted `cwd` **plus** deleted `BASH_SOURCE`/`fd 255`.
- Explicitly EXCLUDE `exe` — a `claude` self-update unlinks the running binary (~11 live hits).
- NEVER match on stdout/stderr alone: that shape **is** this repo's own `scripts/tmpfs-guard.sh`
  cron instance (verbatim pid 704313 case in the issue, 75s old and healthy). A reaper keyed on
  it kills the tmpfs guard on its next cron tick.
- Fail toward **leaving the process alive** on any unreadable `/proc` entry, unparseable link,
  or ambiguity.
- Own-uid only, no sudo, matching `tmpfs-guard.sh`'s posture. Do not change that script's
  fd-skip behaviour — it is file-scoped and correct for live runs.
- Zero hits from the four-way conjunction on the probed box is evidence of **specificity** in a
  sample containing no orphan. It is **not** evidence of sensitivity. Prose must preserve this.

## Test obligations (all binding)

- Positive arm, synthesized per `cq-test-fixtures-synthesized-only`: a process whose cwd
  directory and executing script are both unlinked after launch — must be flagged.
- Negative arm, the real false positive: the `tmpfs-guard.sh` cron shape (deleted stdout, live
  cwd, live script) — must NOT be flagged.
- Mutation battery: every new check mutated out individually, suite confirmed to redden. Prior
  art to read first:
  `knowledge-base/project/learnings/2026-08-14-every-defect-was-a-guard-that-could-not-fail-and-no-instrument-found-more-than-two.md`
  — the preceding PR in this area shipped nine guards that could not be driven red.
