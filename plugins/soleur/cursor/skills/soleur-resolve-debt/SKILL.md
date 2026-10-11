---
name: soleur-resolve-debt
description: "This skill should be used when triaging or closing open entries in the technical-debt ledger. Lists open debt, walks the operator through closing one with a linked GitHub issue."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/resolve-debt/SKILL.md`, relative to the plugin root.
