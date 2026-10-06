---
name: soleur-heal-skill
description: "This skill should be used when a skill has incorrect instructions, outdated API references, or wrong parameters. Detects, diffs, applies after approval."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/heal-skill/SKILL.md`, relative to the plugin root.
