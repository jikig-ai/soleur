---
name: soleur-git-worktree
description: "This skill should be used when managing Git worktrees for isolated parallel development. It handles creating, listing, switching, and cleaning up worktrees with a simple interactive interface."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/git-worktree/SKILL.md`, relative to the plugin root.
