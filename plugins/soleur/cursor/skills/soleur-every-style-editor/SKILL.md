---
name: soleur-every-style-editor
description: "This skill should be used when reviewing or editing copy for adherence to Every's style guide. It provides systematic line-by-line review for grammar, punctuation, mechanics, and style compliance."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/every-style-editor/SKILL.md`, relative to the plugin root.
