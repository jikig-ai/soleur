---
name: soleur-cron-delete
description: "This skill should be used to delete a scheduled cron workflow by name — the first-class Delete verb that runs the delete step of soleur:schedule, with a confirm gate."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/cron-delete/SKILL.md`, relative to the plugin root.
