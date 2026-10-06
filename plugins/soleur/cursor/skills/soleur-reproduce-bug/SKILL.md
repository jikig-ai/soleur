---
name: soleur-reproduce-bug
description: "This skill should be used when reproducing and investigating a bug using logs, console inspection, and browser screenshots. It systematically investigates GitHub issues through log analysis, code inspection, and visual reproduction with Playwright."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/reproduce-bug/SKILL.md`, relative to the plugin root.
