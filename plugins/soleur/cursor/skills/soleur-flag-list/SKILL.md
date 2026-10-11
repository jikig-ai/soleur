---
name: soleur-flag-list
description: "This skill should be used to read and audit all runtime feature flags before a promotion or delete decision: Flagsmith state, server.ts code-wiring, live Doppler dev/prd values, and per-segment overrides, with drift detection."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. A nonempty CURSOR_INVOKED_AS classifies the session as cursor. Hooks are not a live registry yet, and this does not block a commit.

Read `skills/flag-list/SKILL.md`, relative to the plugin root.
