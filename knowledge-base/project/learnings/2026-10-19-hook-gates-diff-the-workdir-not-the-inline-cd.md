# Hook gates diff the exec call's workdir, not the `cd` inside the command

## Problem

Two commit attempts in a worktree were rejected by hook gates that saw state
belonging to a different tree:

1. `context-reviewed-gate.sh` BLOCKED a commit claiming a `last_reviewed:` line
   was removed — while the staged diff contained zero `last_reviewed` strings.
2. A Devin-side guard reported "Committing directly to main/master is not
   allowed" for a command whose `cd` targeted a feature-branch worktree.

## Root cause

Hook/permission gates evaluate the command's **effective working directory at
call time**, which is the exec tool's `workdir` parameter — not a `cd` that
runs later inside the command text. `context-reviewed-gate.sh` computes
`git diff HEAD` / `--cached` in `$PWD`; with no `workdir` set, `$PWD` was the
bare repository root, whose own index/HEAD diff legitimately contained
`last_reviewed` changes from other in-flight state. The same mechanism made
the main-branch commit guard see the bare root's `main` HEAD instead of the
worktree's feature branch.

## Prevention

- For worktree commits, ALWAYS pass the `workdir` exec parameter (or rely on
  `git -C <abs-path>` — `git -C` also satisfied the main-branch guard because it
  keys on the command string) — never rely on a `cd` prefix inside the command.
- When a hook's denial describes state you cannot reproduce in your tree
  ("your diff removes X"), re-run the identical command with `workdir` set
  before concluding the hook is wrong — the state it describes may be real,
  just in a different tree.
- Retrying an identical rejected command can succeed for the wrong reason:
  the first rejection also ate the `git add` in the same call, so the retry
  diffed a different staged set. Verify `git status --short` before retrying.

Tags: hooks, worktrees, guardrails, tooling
