---
name: soleur-brainstorm-techniques
description: "This skill should be used before implementing features or making changes. It guides exploring user intent, approaches, and design decisions when a request has multiple valid interpretations or ambiguous requirements needing clarification."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.

Read `skills/brainstorm-techniques/SKILL.md`, relative to the plugin root.
