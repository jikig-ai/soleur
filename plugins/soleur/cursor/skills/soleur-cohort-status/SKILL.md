---
name: soleur-cohort-status
description: "This skill should be used when the operator asks for the alpha-tester cohort status — recruitment tally, checkpoint state, quiet flags. Pull-based; no dashboard."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/cohort-status/SKILL.md`, relative to the plugin root.
