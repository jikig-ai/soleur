---
name: soleur-resolve-pr-parallel
description: "This skill should be used when resolving all PR comments using parallel processing. It fetches unresolved comments, spawns parallel resolver agents, and verifies all threads are resolved."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/resolve-pr-parallel/SKILL.md`, relative to the plugin root.
