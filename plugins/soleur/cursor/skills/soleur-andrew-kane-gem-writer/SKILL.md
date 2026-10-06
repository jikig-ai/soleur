---
name: soleur-andrew-kane-gem-writer
description: "This skill should be used when writing Ruby gems following Andrew Kane's patterns. It applies when creating new gems, refactoring existing gems, or designing gem APIs with clean, minimal, production-ready code."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/andrew-kane-gem-writer/SKILL.md`, relative to the plugin root.
