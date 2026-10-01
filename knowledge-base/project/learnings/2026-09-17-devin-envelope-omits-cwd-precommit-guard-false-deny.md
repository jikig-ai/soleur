---
title: "Devin envelope omits .cwd — precommit-guard resolves the wrong repo and false-denies worktree commits"
date: 2026-09-17
category: integration-issues
tags: [devin, hooks, guardrails, worktree, false-positive, cwd-envelope]
issue: 8254
status: filed
---

# Learning: `git commit` in a worktree is false-denied under Devin — attach `git -C <dir>`

## Problem

In a Devin CLI session, a bare `git commit` run inside `.worktrees/feat-<name>/` (on a feature branch) is denied by `.claude/hooks/guardrails.sh` `block-commit-on-main` with "BLOCKED: Committing directly to main/master is not allowed." Observed twice in this session; the branch was verifiably `feat-devin-upstream-asks-posture`.

## Root cause

The hook passes the tool envelope's `.cwd` to `plugins/soleur/scripts/precommit-guard.sh` as `--cwd`. Devin's tool envelope **omits `.cwd` entirely** (measured — `envelope-capture.md`), so the guard falls through its resolution chain (`last_cd` → `--cwd` → `$PWD`) to the hook process's `$PWD`, which is the **project root** — the main checkout, on `main`. The branch check then judges the wrong repository and denies.

This is the `.cwd`-omission row of the capability matrix materializing as a live guard fault: under Devin, ANY repo-context-dependent hook that trusts the envelope's `.cwd` silently resolves the project root instead of the exec's actual `workdir`.

## Solution

Give the guard a resolvable directory on the command line — it explicitly honors `git -C` (and `cd`-chains, `GIT_DIR=`, `--git-dir=`):

```bash
# denied under Devin:
git commit -m "…"          # hook resolves $PWD = main checkout → false deny

# allowed — guard resolves -C dir to the worktree's real branch:
git -C /abs/path/.worktrees/feat-<name> commit -m "…"
```

## Key insight

Under Devin, a hook can never see the exec tool's `workdir` parameter — it is not in the envelope. Any repo-scoped hook invariant that depends on "where the command runs" is broken in the Devin arm unless the command string itself carries the directory (`git -C`, `cd`, `--git-dir`). Design implication both ways: (a) hook code should treat absent `.cwd` as unresolvable rather than silently falling back to `$PWD`; (b) agents under Devin should attach `git -C` to repo-mutating commands in worktrees so every guard judges the right repo.

## Session Errors

- **`git commit` denied twice (false positive).** — Recovery: `git -C <worktree> commit` (the guard resolves `-C` correctly). — Prevention: tracked as defect #8254; interim rule — under Devin, always attach `git -C <dir>` to worktree commits.
- **`gh issue create` rejected (missing `--milestone`).** — Recovery: added `--milestone "Post-MVP / Later"`. — Prevention: already hook-enforced; no action.
- **`cleanup-merged` lock contended at session start.** — Recovery: skipped, non-blocking. — Prevention: none (transient by design).
- **`Can't find lefthook in PATH` warnings.** — Recovery: non-blocking env noise. — Prevention: none.

## Cross-references

- Defect filing: #8254
- Envelope measurement: `knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md`
- Capability matrix `.cwd` row: `plugins/soleur/devin/INSTRUCTIONS.md` §Hooks and completion
- Guard sources: `.claude/hooks/guardrails.sh` (block-commit-on-main), `plugins/soleur/scripts/precommit-guard.sh`
