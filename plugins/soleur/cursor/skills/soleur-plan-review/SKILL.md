---
name: soleur-plan-review
description: "This skill should be used when having multiple specialized agents review a plan in parallel. It spawns DHH, Kieran, and code simplicity reviewers to provide diverse feedback on implementation plans."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/plan-review/SKILL.md`, relative to the plugin root.
