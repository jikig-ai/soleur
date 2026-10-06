---
name: soleur-preflight
description: "This skill should be used when running pre-ship checks on migrations, security headers, and lockfiles."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/preflight/SKILL.md`, relative to the plugin root.
