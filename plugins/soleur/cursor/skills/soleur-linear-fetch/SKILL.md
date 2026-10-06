---
name: soleur-linear-fetch
description: "This skill should be used when a user input contains a Linear issue reference (e.g., SOL-39 or linear.app/.../issue/<ID>) and the downstream agent needs the screenshots embedded in the issue as visual context."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/linear-fetch/SKILL.md`, relative to the plugin root.
