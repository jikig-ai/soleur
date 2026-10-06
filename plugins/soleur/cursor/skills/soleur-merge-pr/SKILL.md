---
name: soleur-merge-pr
description: "This skill should be used when merging a feature branch to main with automatic conflict resolution and cleanup."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/merge-pr/SKILL.md`, relative to the plugin root.
