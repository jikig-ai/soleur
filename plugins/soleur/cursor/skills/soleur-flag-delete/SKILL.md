---
name: soleur-flag-delete
description: "This skill should be used to delete a runtime feature flag end-to-end (the inverse of flag-create): removes it from Flagsmith, server.ts RUNTIME_FLAGS, .env.example, the flag-set-role flip.sh map, and Doppler dev+prd, with a WORM audit and typed-yes guardrail."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/flag-delete/SKILL.md`, relative to the plugin root.
