---
title: "Run repository checks from the worktree root"
date: 2026-09-14
category: workflow-issues
---

# Run repository checks from the worktree root

When a command runs with `apps/web-platform` as its working directory, paths
outside that app are no longer repository-relative. A combined check that used
`plugins/soleur/skills/flag-set-role/scripts/flip.sh` therefore failed with
`No such file or directory`. Use an absolute worktree path or run repository
checks from the worktree root, and keep app-local test commands separate.

Vitest's multi-project config also rejects a relative file filter when the
project selector cannot reconcile it with the project root. Use an absolute
worktree file path with `--project unit` or `--project component` for focused
app tests.

The `apply_patch` wrapper resolves relative paths from the bare checkout even
when the shell is in a worktree. Invoke it through `exec_command` with the
worktree as `workdir` so edits land in the active checkout.
