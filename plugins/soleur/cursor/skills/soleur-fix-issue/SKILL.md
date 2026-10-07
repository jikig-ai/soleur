---
name: soleur-fix-issue
description: "This skill should be used to attempt an automated single-file fix for a GitHub issue. Creates a branch, fixes, tests, opens a PR, and labels for auto-merge or human review."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/fix-issue/SKILL.md`, relative to the plugin root.
