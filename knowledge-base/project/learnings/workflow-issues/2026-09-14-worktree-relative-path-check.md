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
