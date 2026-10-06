---
name: soleur-release-docs
description: "This skill should be used when updating documentation metadata after adding or removing plugin components. It updates plugin.json description and README.md counts, then verifies the Eleventy build produces correct output."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `skills/release-docs/SKILL.md`, relative to the plugin root.
