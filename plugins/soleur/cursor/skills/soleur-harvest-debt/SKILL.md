---
name: soleur-harvest-debt
description: "This skill should be used when harvesting inline SOLEUR-DEBT: markers from the codebase into a ledger grouped by file, flagging markers with no upgrade trigger."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/harvest-debt/SKILL.md`, relative to the plugin root.
