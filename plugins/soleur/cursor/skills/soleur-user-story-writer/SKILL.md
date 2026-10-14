---
name: soleur-user-story-writer
description: "This skill should be used when decomposing feature requirements into granular, implementable user stories. It applies Elephant Carpaccio slicing, INVEST criteria, and story prioritization."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/user-story-writer/SKILL.md`, relative to the plugin root.
