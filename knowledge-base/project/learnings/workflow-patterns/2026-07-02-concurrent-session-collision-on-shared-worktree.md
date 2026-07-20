# Learning: Concurrent Claude sessions on one worktree silently destroy uncommitted work

category: workflow-patterns
module: git-worktree / multi-session
date: 2026-07-02
issue: 5875 (PR2 of the agent-sandbox hardening)

## Problem

While implementing PR2 of #5875 in the shared worktree `.worktrees/feat-harden-agent-sandbox-5875`, a **second concurrent `claude` session** working the *same branch* committed PR1 (observability) as `94b8e9965` and, in doing so, **hard-reset the shared working tree** — silently destroying ALL of this session's uncommitted PR2 work: newly-`Write`n files vanished, `Edit`s to tracked files reverted to HEAD, and `git status` reported the tree clean.

The failure was baffling at first because the tool layer reported success: `Write`/`Edit` returned "File created/updated successfully", smoke tests ran green against the files, then minutes later `ls` showed the files gone and `git -C <worktree> status` was clean. The confusion was compounded by the Bash tool's CWD-non-persistence — an early `git status` run from a drifted CWD (the bare-repo root, where tracked files exist as stale synced copies) also showed clean, masking which tree was actually being inspected.

## Root cause

**Multiple Claude sessions operating in the SAME worktree/branch.** `ps -ef | grep 'claude --plugin-dir'` showed THREE concurrent sessions. One session's `git commit` (preceded by a `git reset --hard` / `git checkout -- .` / staged-then-reset flow) wipes another session's *uncommitted* working-tree state. Committed work is safe; uncommitted work is not.

## Detection recipe

Any ONE of these during a worktree session means another session is mutating your tree:
1. `Write`/`Edit` reports success, but `ls "$file"` or `git -C <worktree> status` later shows it absent/clean.
2. `git -C <worktree> reflog` / `git log` shows a HEAD commit you did **not** author (here: `94b8e9965`, a PR you weren't writing).
3. `ps -ef | grep -c 'claude --plugin-dir'` > 1.

Always inspect with `git -C <worktree-abs-path>` (never a bare `git status` whose CWD may have drifted to the bare root).

## Solution (the recovery that worked)

The operator chose an **isolated worktree** (collision-proof):

```bash
# Branch a fresh worktree off the CONCURRENT session's commit, so you inherit
# its landed work (here PR1's ADR + classifier) as your base:
git -C <bare-repo> worktree add -b <feature>-pr2 .worktrees/<feature>-pr2 <their-commit-sha>
# node_modules: symlink from the sibling worktree (already installed) — fast:
ln -s <sibling-worktree>/node_modules <new>/node_modules
ln -s <sibling-worktree>/apps/web-platform/node_modules <new>/apps/web-platform/node_modules
```

Then re-lay the work from context and **commit after every logical unit** — a probe file (`date > PROBE.txt; ls PROBE.txt`) confirmed there was no active per-write revert hook (the wipe was a one-time reset, not continuous), but committing frequently makes any future external reset a no-op against your work (a `reset --hard`/`checkout` cannot touch committed history).

## Key insight

**On a worktree that another session may share, uncommitted work has no durability guarantee across turns.** Treat the working tree as volatile: commit-early-commit-often, and when Write/Edit "success" is contradicted by a later `ls`/`git status`, suspect a concurrent session before suspecting the tool layer. The clean recovery is a *new* branch stacked on the intruding commit, not fighting for the shared branch.

## Session Errors

- **Uncommitted PR2 work destroyed by a concurrent session's commit+reset.** — Recovery: isolated worktree stacked on `94b8e9965` + commit-per-unit. — Prevention: at worktree-session start, `ps -ef | grep -c 'claude --plugin-dir'`; if >1, prefer an isolated branch and commit frequently; never rely on uncommitted state surviving a turn.
- **Brief asserted "PR1 (observability) merged" but it was NOT on `origin/main`** (no `sandbox-startup-classifier.ts`, no PR referenced #5875) — it was only committed on-branch by the concurrent session. — Prevention: verify claimed merge/branch state with `git ls-tree origin/main <path>` + `gh pr list --search` before depending on it (existing "plan-quoted state is a precondition, not a fact" class).
- **Plan-quoted `ADR-077` was stale** (claimed that window by #5766). Canary ADR is **ADR-079**. — Prevention: re-derive the next-free ADR from the directory at work-start (already an existing rule; here the concurrent session's PR1 had already correctly renumbered it).
- **vitest green (14/14) but `tsc --noEmit` red (TS2353)** — a `.test.ts` importing a `.mjs` whose exported function's param type was inferred too narrowly from its destructuring defaults. — Recovery: added JSDoc `@param`/`@returns` to the `.mjs` function. — Prevention: run the project's pinned `./node_modules/.bin/tsc --noEmit` as a work-phase gate (vitest type-checks test files lazily), not just the vitest suite.
- **CWD-non-persistence confusion** — a bare `git status` (no `-C`) ran against the bare-repo root and showed clean, briefly masking the real worktree state. — Prevention: always `git -C <worktree-abs-path>` for state checks in a bare-repo-worktree setup.
- **`[[ cond ]] && rm ...` under `set -euo pipefail`** would abort the function (skipping the state write) when the condition is false. — Recovery: rewrote as `if [[ cond ]]; then rm ... || true; fi`. — Prevention: never use `test && cmd` for optional cleanup under `set -e`; use an `if` block. (one-off, caught pre-commit)
- **2 `ci-deploy.test.sh` failures** ("missing doppler CLI") were environment-specific — `doppler` is installed at `/usr/bin` (a dir the test's mock PATH includes), so the doppler-absent simulation leaks the real binary; passes in CI where doppler is absent. — Prevention: confirmed pre-existing/env-only before treating as a regression (existing "re-run without the env difference" class). (one-off)

## Tags
category: workflow-patterns
module: git-worktree
related: [[2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban]]
