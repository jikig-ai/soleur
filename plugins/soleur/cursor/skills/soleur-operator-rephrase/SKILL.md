---
name: soleur-operator-rephrase
description: "This skill should be used when the last message did not land: say it again in short plain sentences, with no jargon, file paths or issue numbers."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/operator-rephrase/SKILL.md`, relative to the plugin root.
